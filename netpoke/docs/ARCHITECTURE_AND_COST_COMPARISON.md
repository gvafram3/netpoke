# SlowPoke's reference cluster vs. this project's cluster: architecture and cost

## Purpose and a caveat up front

This compares the cluster this project actually measures on against the cluster SlowPoke's own
artifact documents as its reference setup. It is not a comparison against the exact hardware the
published paper's Figure 8 numbers came from; the paper does not state that precisely, and this
project has no way to confirm it independently. What follows uses the artifact's own setup
scripts and instructions (`slowpoke/README.md`, `slowpoke/scripts/setup/`) as the best available
reference point, and says so wherever a number is an estimate rather than a confirmed fact.

## Terms used below, defined plainly

- **vCPU (virtual CPU):** one CPU core's worth of scheduling time, as allocated by a cloud
  provider or by Kubernetes. Two machines both listing "2 vCPU" are giving each container the
  same slice of scheduling time, even if the physical hardware underneath differs.
- **EC2 / GCE:** Amazon's and Google's respective virtual-machine products. An EC2 "instance" and
  a GCE "instance" are the same kind of thing, a rented virtual machine, under different vendor
  names.
- **Instance type / machine type:** a fixed bundle of vCPU count, memory, and network capacity a
  cloud provider sells as one unit, e.g. AWS's `m5.large` (2 vCPU, 8GB RAM) or GCP's
  `e2-standard-2` (2 vCPU, 8GB RAM). Different vendors, similar shape.
- **On-demand pricing:** paying by the hour for a running instance with no upfront commitment,
  as opposed to a discounted reserved or spot rate. The cheaper but less predictable alternative.
- **kubeadm:** the standard command-line tool for bootstrapping a Kubernetes cluster from scratch
  on plain virtual machines, as opposed to using a cloud provider's managed Kubernetes product
  (EKS, GKE). Both this project's cluster and SlowPoke's own reference setup use `kubeadm`
  directly rather than a managed service.
- **Node vs. pod:** a node is one virtual machine, a worker in the cluster. A pod is one running
  instance of a container (here, one microservice plus its `poker` control process) that
  Kubernetes schedules onto some node. Several pods run on each node.
- **Region / availability zone:** a region is a geographic area (e.g. `us-central1`); a zone is
  one physical, independently-failing location within it (e.g. `us-central1-a`). Instances in
  different zones of the same region can still communicate over the region's internal network.
- **vCPU quota:** a cloud account's cap on how many vCPUs it may run simultaneously across all
  running instances, set by the provider (often lower on free-tier or student accounts) and
  raisable on request.

## Side-by-side architecture

| Aspect | SlowPoke's reference setup (AWS) | This project's cluster (GCP) |
|--------|-----------------------------------|-------------------------------|
| Cloud provider | Amazon Web Services (EC2) | Google Cloud Platform (GCE) |
| Cluster bootstrap | `scripts/setup/setup_ec2_cluster.py`, `kubeadm` | `netpoke/infra/gcp/0{1,2}_*.sh`, also `kubeadm` (reuses SlowPoke's own setup approach) |
| Control node | 1 instance running `kubectl` and `main.py` | 1 instance (`netpoke-control`), same role |
| Load generator | A 2nd EC2 instance runs the `wrk` client | A dedicated `netpoke-loadgen` node exists but is unused; the `wrk` client pod is pinned (`client.yaml`, `nodeName: worker1`) to a worker node instead, in both setups' actual client placement |
| Service workers | Example setup script defaults to 12 worker nodes (`m5.large`, 2 vCPU each), reused for every service pod across the whole application graph | 3 worker nodes (`e2-standard-2`, 2 vCPU each); the benchmark YAMLs' node affinity spreads each application's roughly 8-9 services across these 3 nodes rather than one node per service |
| Total vCPU (example sizing) | 12 workers x 2 + control + loadgen $\approx$ 28+ vCPU | 3 workers x 2 + control 2 + loadgen 4 (unused) = 12 vCPU |
| Slowdown mechanism | `poker` + `SIGSTOP`/`SIGCONT`, unmodified | Same `poker`, plus this project's own NetPoke egress-hold addition |
| Reported/measured accuracy | RMSE $\approx$ 2.07% (paper, boutique-equivalent target) | RMSE 2.57% reproduced for the same target (Table B1), closest agreement of any app to the paper's own figure |

## Why the worker count differs, and what it costs

The 12-worker figure comes directly from the artifact's own AWS setup script
(`setup_ec2_cluster.py -d ~/mycluster/ -n 12`, with `12` documented as an example worker count,
adjustable). This project's cluster runs 3 workers instead, a deliberate, budget-driven choice
recorded in `netpoke/infra/gcp/config.env.example`: a standard (non-negotiated) GCP account's
default `CPUS_ALL_REGIONS` quota is 12 vCPU total, and this project's entire cluster, control
node, 3 workers, and the (normally unused) load-generator node, is sized to fit exactly inside
that limit without requesting a quota increase.

This has one concrete consequence worth stating plainly rather than glossing over: each of this
project's 3 worker nodes hosts roughly three times as many service pods as a 12-worker layout
would, since the same number of application services (boutique's 8-9, or a DeathStarBench app's
similar count) is spread across fewer machines. More services sharing a node's CPU and network
stack is a plausible contributor to this cluster's higher RMSE than the paper's own headline
figure, and to some of the run-to-run noise already documented elsewhere in this project
(particularly hotel's volatility). This is a real, load-bearing difference between the two
setups, not merely a cosmetic one, and it is the most likely single explanation for why this
cluster's numbers are noisier than the paper's.

## Estimated cost comparison

Public on-demand pricing changes over time and by region; the figures below are for
order-of-magnitude comparison, not a precise budget.

| Setup | Instances | Approx. on-demand rate | Approx. cost per hour |
|-------|-----------|--------------------------|-------------------------|
| SlowPoke reference (AWS, 12 workers) | 1 control + 1 loadgen + 12 workers (`m5.large`) $\approx$ 14 instances | `m5.large` $\approx$ US\$0.096/hr | $\approx$ US\$1.30-1.40/hr |
| This project (GCP, 3 workers, loadgen unused) | 1 control (`e2-standard-2`) + 3 workers (`e2-standard-2`) [+ 1 unused loadgen] | $\approx$ US\$0.03-0.04/hr per `e2-standard-2` | $\approx$ US\$0.40/hr (as measured and documented in `netpoke/infra/gcp/README.md`) |

The reference setup, at its documented example size, costs on the order of 3x this project's
cluster per hour, driven almost entirely by running roughly four times as many worker instances.
A single 2.5-hour reproducible-baseline run (`run_reproducible.sh`, per SlowPoke's own
`INSTRUCTIONS.md`) would cost roughly US\$3-3.50 on the reference-sized cluster versus the
roughly US\$1-2 this project's `netpoke/infra/gcp/README.md` already documents for the same run
on this project's cluster.

## What this means for interpreting this project's results

The cluster-size difference is the honest, structural reason this project's baseline RMSE
(Table B1) sits above the paper's reported 2.07% for every application except boutique, which
comes closest (2.57%). It is also a plausible contributor, alongside genuine I/O-bound behaviour,
to the run-to-run volatility documented for hotel throughout this project (Chapters 3, 6, and 7).
None of this weakens the core comparisons this thesis makes, since every comparison in Tables
N1 through N3 is SIGSTOP-only versus NetPoke-on on the *same* cluster, under the *same* sizing
constraints, so cluster-size effects apply equally to both sides of each comparison. It does mean
that this project's absolute RMSE figures should not be read as a direct, apples-to-apples
replication of the paper's headline 2.07%, only as an internally consistent baseline against
which this project's own before/after comparisons are measured.
