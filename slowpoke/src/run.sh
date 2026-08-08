#!/bin/bash

export SLOWPOKE_TOP=${SLOWPOKE_TOP:-$(cd "${BASH_SOURCE%/*}/.." && pwd -P)}
echo "SLOWPOKE_TOP is set to $SLOWPOKE_TOP"

cd $(dirname $0)

benchmark=${1:-boutique}
request=${2:-home}
thread=${3:-16}
conn=${4:-512}
TOTAL_REQ=${5:-50000}

duration=60

YAML_PATH=$SLOWPOKE_TOP/evaluation/$benchmark/yamls
if [[ $benchmark == "synthetic" ]]; then
    YAML_PATH=$SLOWPOKE_TOP/evaluation/$benchmark/$request/yamls
fi
# SLOWPOKE_YAML_SUBDIR overrides which yamls/<subdir> to deploy from,
# independent of whether NetPoke itself is active -- needed for the
# SIGSTOP-only-but-instrumented case (netpoke-sigstop image: same *-netpoke
# build with the poker.c pause-window fix, SLOWPOKE_NETPOKE forced to "0" in
# the yaml itself), which still needs the *-netpoke image but must NOT be
# selected by the SLOWPOKE_NETPOKE=="1" check below.
if [[ -n "${SLOWPOKE_YAML_SUBDIR:-}" && -d "$SLOWPOKE_TOP/evaluation/$benchmark/yamls/$SLOWPOKE_YAML_SUBDIR" ]]; then
    YAML_PATH=$SLOWPOKE_TOP/evaluation/$benchmark/yamls/$SLOWPOKE_YAML_SUBDIR
    echo "[run.sh] deploying from $YAML_PATH (SLOWPOKE_YAML_SUBDIR override)"
elif [[ "${SLOWPOKE_NETPOKE:-}" == "1" && -d "$SLOWPOKE_TOP/evaluation/$benchmark/yamls/netpoke" ]]; then
    YAML_PATH=$SLOWPOKE_TOP/evaluation/$benchmark/yamls/netpoke
    echo "[run.sh] NetPoke: deploying from $YAML_PATH"
fi

supported_benchmarks=("boutique" "social" "movie" "hotel" "synthetic")

check_benchmark_supported() {
    local benchmark=$1
    for b in "${supported_benchmarks[@]}"; do
        if [[ $b == $benchmark ]]; then
            return 0
        fi
    done
    return 1
}

check_connectivity() {
    local pod_name=$1
    local service_name=$2
    # if service name is the same as the pod name (prefix), skip the check
    if [[ $1 == $2* ]]; then
        return 0
    fi
    # if the pod is ubuntu client
    if [[ $pod_name == *"ubuntu-client"* ]]; then
        kubectl exec $pod_name -- curl $service_name:80/heartbeat --max-time 1 | grep Heartbeat > /dev/null
        return $?
    fi
    kubectl exec $pod_name -- sh -c "(echo -e \"GET /heartbeat HTTP/1.1\r\nHost: $service_name\r\nConnection: close\r\n\r\n\") \
        | nc -w 1 $service_name 80" | grep Heartbeat > /dev/null
    return $?
}

check_connectivity_all(){
    echo "[run.sh] Checking heartbeat for all services"
    # if "grpc" in request, ignore
    if [[ $request == *grpc* ]]; then
        sleep 5
        return 0
    fi
    while true
    do
        all_connected=1
        for pod in $(kubectl get pods | grep -v -E 'NAME' | cut -f 1 -d " ")
        do
            for service in $(kubectl get svc | grep -v -E 'NAME|kube' | cut -f 1 -d " ")
            do
                check_connectivity $pod $service
                if [ $? -ne 0 ]
                then
                    echo "[run.sh] $pod cannot connect to $service"
                    all_connected=0
                    break
                fi
            done
            if [ $all_connected -eq 0 ]
            then
                break
            fi
        done
        if [ $all_connected -eq 1 ]
        then
            echo "[run.sh] All pods can connect to all services"
            break
        fi
    done
}

fix_req_num() {
    local benchmark=$1
    local client=$2
    counter=$((TOTAL_REQ / thread))
    # Cap counter so every thread can finish within duration at current speed.
    # Without this, L1/L2 injection drops throughput so low the counter is
    # unreachable before wrk times out, so done() fires with no stop times.
    if [[ -n "${speed:-}" && -n "${duration:-}" && "${speed}" != "0" ]]; then
        local max_counter
        # Cap counter so every thread can finish within duration.
        # Use speed/4 as pessimistic estimate (poker SIGSTOP can drop throughput
        # 2-4x below warmup; netem injection is already reflected in warmup speed).
        # Never cap below 3 so done() always fires with usable stop times.
        max_counter=$(awk -v s="$speed" -v t="$thread" -v d="$duration" \
            'BEGIN{actual=s/4; c=int(0.9*actual/t*d); if(c<3)c=3; print c}')
        if (( max_counter < counter )); then
            echo "[run.sh] fix_req_num: capping counter $counter -> $max_counter (speed=${speed} duration=${duration})"
            counter=$max_counter
        fi
    fi
    PER_THREAD_COUNTER=$counter envsubst < $SLOWPOKE_TOP/client/fix_req_n.lua > /tmp/temp_fix_req_n.lua
    kubectl cp /tmp/temp_fix_req_n.lua ${client}:/wrk/fix_req_n.lua
    rm /tmp/temp_fix_req_n.lua  # clean up
    if [[ $benchmark == *"boutique"* ]]; then
        # Reset mix.lua from .orig before appending to avoid accumulation on retries.
        kubectl exec ${client} -- /bin/sh -c "
            orig=/wrk/scripts/online-boutique/${request}.lua.orig
            if [ ! -f \"\$orig\" ]; then cp /wrk/scripts/online-boutique/${request}.lua \"\$orig\"; fi
            cp \"\$orig\" /wrk/scripts/online-boutique/${request}.lua
            cat /wrk/fix_req_n.lua >> /wrk/scripts/online-boutique/${request}.lua
        "
        return
    fi
}

warmup_and_speed() {
    local client=$1
    local thread=$2
    local conn=$3
    local host=$4
    local script="-s $5"
    if [[ -z $5 ]]; then
        script=""
    fi
    output=$(kubectl exec $client -- /wrk/wrk -t${thread} -c${conn} --timeout 3s -d3s -L $script $host)
    echo $output
}

start_rust_proxy() {
    local benchmark=$1
    local ubuntu_client=$2
    echo "[run.sh] Starting the rust proxy first for $benchmark"
    # kubectl exec blocks until the remote process exits. A background proxy still
    # holds stdout/stderr open on the exec session, which hung hotel/social/movie
    # after boutique in multi-node runs. nohup + redirect detaches I/O.
    # Do not use pkill -f: it matches the kubectl exec shell and exits 143.
    kubectl exec "$ubuntu_client" -- pkill -x proxy 2>/dev/null || true
    sleep 1
    kubectl exec "$ubuntu_client" -- sh -c \
        "nohup /mucache/proxy/target/release/proxy ${benchmark} \
           >/tmp/proxy-${benchmark}.log 2>&1 </dev/null & exit 0"
    local i ready=0
    for i in $(seq 1 45); do
        if kubectl exec "$ubuntu_client" -- curl -sf --max-time 2 http://localhost:3000/heartbeat 2>/dev/null \
            | grep -q Heartbeat; then
            ready=1
            break
        fi
        if kubectl exec "$ubuntu_client" -- grep -q 'Reading' "/tmp/proxy-${benchmark}.log" 2>/dev/null; then
            if kubectl exec "$ubuntu_client" -- /wrk/wrk -t1 -c4 --timeout 3s -d1s http://localhost:3000 2>/dev/null \
                | grep -q 'Requests/sec:'; then
                ready=1
                break
            fi
        fi
        sleep 1
    done
    if (( ready )); then
        echo "[run.sh] Proxy ready on localhost:3000 (after ${i}s)"
    else
        echo "[run.sh] WARNING: proxy heartbeat not confirmed; continuing (see /tmp/proxy-${benchmark}.log)"
        kubectl exec "$ubuntu_client" -- tail -25 "/tmp/proxy-${benchmark}.log" 2>/dev/null || true
    fi
}

run_test() {
    local benchmark=$1
    local ubuntu_client=$(kubectl get pod | grep ubuntu-client- | cut -f 1 -d " ") 

    if [[ $benchmark != "boutique" && $benchmark != "synthetic" ]]; then
        start_rust_proxy $benchmark $ubuntu_client
    fi

    echo "[run.sh] Running warmup test" 
    if [[ $benchmark == "boutique" ]]; then
       # run the load generator
        echo "[run.sh] /wrk/wrk -t${thread} -c${conn} --timeout 3s -d3s -L -s /wrk/scripts/online-boutique/${request}.lua http://frontend:80"
        output=$(kubectl exec $ubuntu_client -- /wrk/wrk -t${thread} -c${conn} --timeout 3s -d3s -L -s /wrk/scripts/online-boutique/${request}.lua http://frontend:80)
    elif [[ $benchmark == "synthetic" ]]; then
        echo "[run.sh] /wrk/wrk -t${thread} -c${conn} --timeout 3s -d3s -L http://service0:80/endpoint1"
        output=$(kubectl exec $ubuntu_client -- /wrk/wrk -t${thread} -c${conn} --timeout 3s -d3s -L http://service0:80/endpoint1)
    else 
        echo "[run.sh] /wrk/wrk -t${thread} -c${conn} --timeout 3s -d3s -L http://localhost:3000"
        output=$(kubectl exec $ubuntu_client -- /wrk/wrk -t${thread} -c${conn} --timeout 3s -d3s -L http://localhost:3000)
    fi
    echo "$output"

    # get the speed of the warmup test and estimate the duration
    speed=$(echo "$output" | grep "Requests/sec:" | awk '{print $2}')
    if [[ -z "$speed" || "$speed" == "0" ]]; then
        echo "[run.sh] ERROR: warmup produced no throughput (wrk/proxy failed)"
        echo "$output"
        return 1
    fi
    # Need enough wrk time for every thread to hit fix_req_n.lua's per-thread counter.
    # Old cap at 200s caused L2 io_gap runs (100k req @ ~500 req/s) to end early → Lua panic → status 1.
    duration=$(awk -v r="$TOTAL_REQ" -v s="$speed" 'BEGIN{d=int(1.5*r/s); if(d<120)d=120; if(d>600)d=600; print d}')
    echo "[run.sh] Speed is $speed, duration is $duration"

    echo "[run.sh] Fix the request number."
    fix_req_num $benchmark $ubuntu_client

    echo "[run.sh] Running the actual test"
    sleep 10
    if [[ $benchmark == "boutique" ]]; then
        echo "[run.sh] /wrk/wrk --timeout 20s -t${thread} -c${conn} -d${duration}s -L -s /wrk/scripts/online-boutique/${request}.lua http://frontend:80"
        kubectl exec $ubuntu_client -- /wrk/wrk --timeout 20s -t${thread} -c${conn} -d${duration}s -L -s /wrk/scripts/online-boutique/${request}.lua http://frontend:80
    elif [[ $benchmark == "synthetic" ]]; then
        echo "[run.sh] /wrk/wrk --timeout 20s -t${thread} -c${conn} -d${duration}s -L -s /wrk/fix_req_n.lua http://service0:80/endpoint1"
        # kubectl exec $ubuntu_client -- /wrk/wrk --timeout 20s -t${thread} -c${conn} -d20s -L http://service0:80/endpoint1
        kubectl exec $ubuntu_client -- /wrk/wrk --timeout 20s -t${thread} -c${conn} -d${duration}s -L -s /wrk/fix_req_n.lua http://service0:80/endpoint1
    else
        echo "[run.sh] /wrk/wrk --timeout 20s -t${thread} -c${conn} -d${duration}s -s /wrk/fix_req_n.lua -L http://localhost:3000"
        kubectl exec $ubuntu_client -- /wrk/wrk --timeout 20s -t${thread} -c${conn} -d${duration}s -s /wrk/fix_req_n.lua -L http://localhost:3000
    fi
}

populate() {
    local ubuntu_client=$(kubectl get pod | grep ubuntu-client- | cut -f 1 -d " ") 
    local benchmark=$1
    if [[ $benchmark == "boutique" ]]; then
        echo "[run.sh] No population needed for $benchmark"
        return
    fi
    if [[ $benchmark == "hotel" || $benchmark == "movie" ]]; then
        local analysis_src="$SLOWPOKE_TOP/evaluation/$benchmark/data/analysis.txt"
        echo "[run.sh] Copying $analysis_src to $ubuntu_client:/analysis.txt"
        if [[ ! -f "$analysis_src" ]]; then
            echo "[run.sh] ERROR: missing $analysis_src"
            return 1
        fi
        kubectl cp "$analysis_src" "$ubuntu_client:/analysis.txt"
        kubectl exec "$ubuntu_client" -- test -s /analysis.txt || {
            echo "[run.sh] ERROR: /analysis.txt not on client after kubectl cp"
            return 1
        }
        echo "[run.sh] Finished populating $benchmark"
        return
    fi
    echo "[run.sh] Populating social benchmark"
    bash $SLOWPOKE_TOP/evaluation/$benchmark/populate.sh 
    echo "[run.sh] Copying $SLOWPOKE_TOP/evaluation/$benchmark/data/analysis.txt to $ubuntu_client:/analysis.txt"
    kubectl cp $SLOWPOKE_TOP/evaluation/$benchmark/data/analysis.txt $ubuntu_client:/analysis.txt
    echo "[run.sh] Finished populating $benchmark"
}

check_benchmark_supported $benchmark
if [ $? -ne 0 ]; then
    echo "[run.sh] Benchmark $benchmark is not supported"
    exit 1
fi

echo "[run.sh] Running benchmark $benchmark with request $request, thread $thread, conn $conn, duration $duration"

# delete all services
echo "[run.sh] Deleting all services"
kubectl delete -f $YAML_PATH --ignore-not-found=true
kubectl delete -f $SLOWPOKE_TOP/client/client.yaml --ignore-not-found=true
# wait for all pods to be deleted
echo "[run.sh] Waiting for all pods to be deleted"
while [[ $(kubectl get pods -n default 2>/dev/null | grep -v NAME | wc -l) -gt 0 ]]; do
    sleep 1
done

# deploy all services
echo "[run.sh] Deploying all services"
for file in $(ls -d $YAML_PATH/*.yaml)
do
    envsubst < $file | kubectl apply -f - 
done

kubectl get pod | grep ubuntu-client- 
if [ $? -ne 0 ]
then
    echo "[run.sh] Client pod not found, deploying client"
    envsubst < $SLOWPOKE_TOP/client/client.yaml | kubectl apply -f -
fi

# wait until all pods are ready by checking the log to see if the "server started" message is printed
echo "[run.sh] Waiting for all pods to be running"
while [[ $(kubectl get pods | grep -v -E 'Running|Completed|STATUS' | wc -l) -ne 0 ]]; do
  sleep 1
done
# Accept 1/1, 2/2, … (boutique L2 shipping netem sidecar is 2/2).
echo "[run.sh] Waiting for all pod containers to be ready"
while kubectl get pods --no-headers 2>/dev/null \
    | grep -vqE '^[^ ]+ +([0-9]+)/\1 +(Running|Completed) '; do
  sleep 1
done
echo "[run.sh] All pods are running"


check_connectivity_all


if [[ $benchmark != "synthetic" ]]; then
    populate $benchmark
fi

sleep 5

run_test $benchmark &
pid=$!

# sleep while wrk runs (artifact timing)
sleep $(echo "$duration*0.8" | bc -l)
echo "[run.sh] Checking the resource usage"
kubectl top pods

wait $pid
status=$?
echo "[run.sh] Test finished with status $status"
exit $status
