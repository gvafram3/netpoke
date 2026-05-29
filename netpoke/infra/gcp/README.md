# NetPoke GCP cluster (runbook)

This folder builds a multi-node Kubernetes cluster on Google Cloud that is close
in spirit to the cluster SlowPoke used in the paper (a dedicated control node, a
dedicated load-generator node, and several service-worker nodes). It exists
because running everything on one VM with Kind creates resource contention that
corrupts throughput measurements.

The scripts reuse SlowPoke's own setup scripts (`slowpoke/scripts/setup/`), so we
install Kubernetes exactly the way the original authors did.

## What gets created

| Kubernetes node | VM name              | Size           | Role                              |
|-----------------|----------------------|----------------|-----------------------------------|
| control-plane   | netpoke-control      | e2-standard-4  | Kubernetes control plane          |
| loadgen         | netpoke-loadgen      | e2-standard-4  | runs the `wrk` workload generator |
| worker1..worker6| netpoke-worker1..6   | e2-standard-2  | run the microservices             |

That is 8 VMs by default (1 + 1 + 6). You can change the counts and sizes in
`config.env`.

## Budget

- VMs are billed **only while running**. The default 8-VM cluster costs roughly
  **US$0.67 per hour**, so a 2.5-hour measurement run is about **US$2–3**
  including setup time.
- **Always run `./03_teardown.sh` when you finish a batch of experiments.** This
  deletes the VMs so they stop costing anything.
- Do code development, image builds, and quick smoke tests on the existing
  single `slowpoke-vm` (with Kind) instead of this cluster, and **stop that VM
  when idle** too: `gcloud compute instances stop slowpoke-vm --zone us-central1-a`.
- Set a billing budget alert in the GCP console (Billing -> Budgets & alerts) at,
  say, US$100 so you are warned well before the US$130 ceiling.

## One-time setup

You run these from a machine that has the `gcloud` tool and this repository
(your `slowpoke-vm` already has both). From `~/netpoke`:

```bash
cd netpoke/infra/gcp
cp config.env.example config.env
```

The defaults in `config.env` already match your project and zone. Edit only if
you want a different size or worker count.

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

SSH into the control node and work from there:

```bash
gcloud compute ssh netpoke-control --zone us-central1-a
```

On the control node, clone this repo (or copy the `slowpoke/` folder over),
build/load the images, deploy a benchmark, and run experiments. The benchmark
YAMLs pin services to nodes named `worker1`, `worker2`, and so on, which is why
the service nodes use exactly those names. (A follow-up step will re-map the
boutique service affinities across `worker1..worker6` and point the client at the
`loadgen` node; see the project notes.)

## Tear the cluster down (do this when done)

```bash
./03_teardown.sh
```

It asks for confirmation, then deletes the VMs and the firewall rule.

## Troubleshooting

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
