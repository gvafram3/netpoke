# Raw baseline logs (L0)

Place cluster `*_medium.log` files here after sync from netpoke-control.

```bash
# On netpoke-control
ls ~/slowpoke/evaluation/results/*_medium.log

# Cloud Shell → local repo
gcloud compute scp --zone=us-central1-a \
  'aframviscagyebi@netpoke-control:~/slowpoke/evaluation/results/{boutique,hotel,social,movie}_medium.log' \
  netpoke/results/cluster/baseline/logs/
```

Files are listed in git once synced (typically 100–200 KB each).
