# NetPoke GCP cluster (runbook)

This folder builds a multi-node Kubernetes cluster on Google Cloud that is close
in spirit to the cluster SlowPoke used in the paper (a dedicated control node, a
dedicated load-generator node, and several service-worker nodes). It exists
because running everything on one VM with Kind creates resource contention that
corrupts throughput measurements.

The scripts reuse SlowPoke's own setup scripts (`slowpoke/scripts/setup/`), so we
install Kubernetes exactly the way the original authors did.

## What gets created

The default sizing fits a standard GCP project's **12-vCPU global quota**
(`CPUS_ALL_REGIONS`):

| Kubernetes node  | VM name            | Size           | vCPU | Role                              |
|------------------|--------------------|----------------|------|-----------------------------------|
| control-plane    | netpoke-control    | e2-standard-2  | 2    | Kubernetes control plane          |
| loadgen          | netpoke-loadgen    | e2-standard-4  | 4    | runs the `wrk` workload generator |
| worker1..worker3 | netpoke-worker1..3 | e2-standard-2  | 2 ea | run the microservices             |

Total: 5 VMs, 12 vCPU (2 + 4 + 3x2). You can change the counts and sizes in
`config.env` if you raise your project's quota.

> Because the project quota is 12 vCPU and `slowpoke-vm` already uses 4, you must
> **stop `slowpoke-vm`** before bringing the cluster up, and run these scripts
> from **Cloud Shell** (which does not count against the vCPU quota) rather than
> from `slowpoke-vm`.

## Budget

- VMs are billed **only while running**. This 5-VM cluster costs roughly
  **US$0.40 per hour**, so a 2.5-hour measurement run is about **US$1–2**
  including setup time.
- **Always run `./03_teardown.sh` when you finish a batch of experiments.** This
  deletes the VMs so they stop costing anything.
- Keep `slowpoke-vm` **stopped** unless you are actively building images or doing
  code work on it: `gcloud compute instances stop slowpoke-vm --zone us-central1-a`.
- Set a billing budget alert in the GCP console (Billing -> Budgets & alerts) at,
  say, US$100 so you are warned well before the US$130 ceiling.

## One-time setup (in Cloud Shell)

Open Cloud Shell from the GCP console (the `>_` icon, top-right), then:

```bash
git clone https://github.com/gvafram3/netpoke.git
cd netpoke/infra/gcp
cp config.env.example config.env
./diagnose_cluster.sh
```

The defaults in `config.env` already match your project and zone. Edit only if
you want a different size or worker count.

## Check cluster state (after step 1 or manual VM changes)

```bash
./diagnose_cluster.sh
```

This lists every VM, zones, RUNNING/TERMINATED status, firewall rule, and SSH
reachability. Fix anything flagged before step 2.

## Bring the cluster up

```bash
# Step 1: create the VMs (about 1 minute)
./01_create_cluster.sh

# wait ~60 seconds for the VMs to finish booting, then:

# Step 2: install Kubernetes and join all nodes (several minutes)
./02_initialize_cluster.sh
```

When step 2 finishes it prints `kubectl get nodes`. All nodes should reach the
`Ready` state within a minute or two.

## Use the cluster

SSH into the control node (use the SSH button on the VM list page, or):

```bash
gcloud compute ssh netpoke-control --zone us-central1-a
```

On the control node, clone this repo (or copy the `slowpoke/` folder over),
build/load the images, deploy a benchmark, and run experiments. The benchmark
YAMLs pin services to nodes named `worker1`, `worker2`, and `worker3`, which is
why the service nodes use exactly those names. (A follow-up step will spread the
boutique services across `worker1..worker3` and point the client at the
`loadgen` node; see the project notes.)

## Tear the cluster down (do this when done)

```bash
./03_teardown.sh
```

It asks for confirmation, then deletes the VMs and the firewall rule.

## Troubleshooting

- **`Quota 'CPUS_ALL_REGIONS' exceeded`:** something is still using vCPUs. Make
  sure `slowpoke-vm` is stopped and no leftover `netpoke-*` VMs remain, then
  retry. The default config is built to fit exactly 12 vCPU.
- **`gcloud` asks about SSH keys the first time:** accept the defaults; it
  generates a key pair and reuses it afterwards.
- **A node is stuck `NotReady`:** give it two minutes (the network plugin takes a
  moment). If it persists, from the control node run
  `kubectl describe node <name>` to see why.
- **Step 2 fails partway:** it is safe to re-run `./02_initialize_cluster.sh`;
  steps that are already done are skipped or are harmless to repeat.
- **A worker fails to join:** SSH into it
  (`gcloud compute ssh netpoke-worker1 --zone us-central1-a`), run
  `sudo kubeadm reset -f --cri-socket unix:///var/run/cri-dockerd.sock`, then
  re-run step 2.
