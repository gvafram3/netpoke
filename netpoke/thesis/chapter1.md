# Chapter 1: Introduction

## 1.1 Introduction

Most large online applications today are built from many small services that run on their own and talk to each other over a network. Each service is looked after by a small team, is released on its own schedule, and is scaled on its own. This way of building software is popular because development and deployment are kept separate, yet that same separation makes the performance of the whole application hard to reason about. A request that looks simple to a user is often served by a chain or a fan-out of internal calls, and the time spent in any one service is shaped by queueing, contention, and synchronisation effects that cannot be seen from the outside (Chow et al., 2014). The scale involved has been documented in industry, where single products are reported to depend on thousands of interacting services with deep and irregular call graphs (Huye et al., 2023).

One question is asked again and again by the engineers who run these systems. Given a limited budget for optimisation work, which service should be improved so that the throughput of the whole application rises by the largest amount? The question is harder than it looks. Because services are linked through shared resources and request dependencies, an improvement to one service is not passed on as a proportional improvement at the application boundary. Effort can be spent on a service that is not on the critical path, in which case the measured benefit is small and the bottleneck simply moves elsewhere. What is needed, before any code is changed, is a sound way of predicting the end-to-end effect of a possible optimisation.

This kind of prediction grew out of causal profiling, a technique introduced for single-machine multithreaded programs by Curtsinger and Berger (2015). The idea is simple once stated. Instead of speeding a region of code up, which cannot be done until the optimisation has actually been written, the profiler slows everything else down by a measured amount. The relative relationships between the components are kept under this change, so the behaviour of the artificially slowed run shows what the genuinely optimised run would have achieved. The idea was carried into the distributed setting by Xie et al. (2026), whose system, SlowPoke, predicts throughput improvements for microservice applications without distributed tracing and without prior knowledge of the call graph. Across four real-world applications, SlowPoke was reported to predict optimisation effects with a root mean squared error of 2.07%, an accuracy that makes causal profiling a credible planning tool for distributed services.

The concern of this study is a limitation in the mechanism that SlowPoke depends on. The slowdown is produced by pausing the operating-system process of each non-target service with the POSIX signal SIGSTOP, and by resuming it later with SIGCONT (Xie et al., 2026). Pausing a process takes time away from the central processing unit, which is exactly the resource that limits a compute-bound service. It does not, however, stop the work that the kernel carries out for that service. While the process is frozen, network packets are still received into socket buffers, acknowledgements are still sent, and pending input and output operations still drain inside the kernel. For a service whose throughput depends on network or database interaction rather than on computation, the pause therefore fails to slow the resource that actually matters. The artificial slowdown is left incomplete, the condition the performance model relies on no longer holds, and the resulting prediction is distorted.

The difference between compute-bound and input/output-bound services is not a minor one. A large share of production services spend their time on database queries, cache lookups, and synchronous calls to other services, and for those services the limiting resource is rarely the processor (Huye et al., 2023). A method that is accurate only when the processor is the bottleneck is therefore limited to a minority of realistic cases. Extending causal profiling so that it stays accurate for input/output-bound services is the problem addressed by this thesis, and the proposed extension, named NetPoke, is the contribution that follows.

## 1.2 Problem Statement

The accuracy of SlowPoke rests on a single assumption. When a non-target service is paused, the paused run is assumed to be equivalent, as far as the application bottleneck is concerned, to a run in which that service had genuinely been slowed. The assumption holds for a compute-bound service, because pausing the process removes processor time in direct proportion to the length of the pause, and processor time is what limits the service.

The assumption breaks when the limiting resource is input and output rather than computation. A pause with SIGSTOP stops only the user-space execution of the process. The kernel keeps acting on the service's open connections during the pause: incoming segments are accepted into receive buffers, the transport layer keeps acknowledging them, and outstanding requests to other services or to storage keep moving towards completion. When the process is resumed, the work that built up during the pause is consumed in a short burst. The real reduction in the service's input/output capacity is therefore much smaller than the length of the pause suggests, and the slowdown that the model believes it applied was not actually applied. Because the bottleneck is no longer preserved, the throughput measured under slowdown no longer matches the throughput that the optimised system would have reached, and the prediction is degraded.

How large the distortion becomes depends on how much input and output is in flight when the pause begins. Where little synchronous interaction is present, the leftover activity is small and the error stays modest. Where a service issues blocking database queries, depends on synchronous calls to other services, or otherwise spends most of its time waiting on the network, the leftover activity is large, and the predicted throughput drifts away from the ground truth. The error is systematic and points in one direction, namely over-prediction, because the slowed system keeps more capacity than the model accounts for, so the optimised throughput is estimated to be higher than it really is.

The limitation is acknowledged, though not measured, by the authors of SlowPoke. It is stated there that the mechanism preserves general processor-time bottlenecks but does not accurately preserve network or disk bottlenecks, because such bottlenecks involve heavy buffering and caching inside the kernel (Xie et al., 2026). The same work suggests, as future work, that network bottlenecks might be handled through a service-mesh sidecar or through input/output throttling, but no such mechanism is designed, built, or evaluated there. A gap therefore remains between the demonstrated promise of distributed causal profiling and its use on the input/output-bound services that fill modern deployments. Closing that gap is the problem this study sets out to solve, by measuring the error, by establishing its cause through direct kernel measurement, and by extending the slowdown so that the pause becomes complete across resources.

## 1.3 Aim

The aim of this study is to design, build, and evaluate an input/output-aware extension to SlowPoke's slowdown mechanism that keeps the bottleneck-equivalence property for network-bound microservices, so that throughput-prediction accuracy for those services is restored to the level SlowPoke already reaches for compute-bound services.

## 1.4 Objectives

The aim is pursued through four objectives:

1. To measure the throughput-prediction error that SlowPoke's pause-only slowdown introduces for input/output-bound services, and to find how that error changes with the amount of input and output performed.
2. To establish the cause of the error through direct kernel-level measurement, using extended Berkeley Packet Filter (eBPF) instrumentation to observe and quantify the input and output that continues during pause windows, and to relate that leftover activity to the prediction error.
3. To design and build an extended slowdown mechanism that, working with the existing pausing controller, also pauses a service's network activity for the same window in which its process is paused, so that the pause is complete across both processor and network.
4. To evaluate the extended mechanism against the SlowPoke baseline on compute-bound and input/output-bound workloads, reporting the gain in prediction accuracy together with the coordination overhead and the cases in which the mechanism does and does not apply.

## 1.5 Research Questions

The study is organised around four research questions, one for each objective:

1. How large is the throughput-prediction error that SlowPoke's pause-only slowdown produces for input/output-bound services, and how does it scale with input/output intensity and with pause duration?
2. Can the input and output that occurs during pause windows be measured directly at the kernel, and does the amount of leftover activity account for the observed prediction error?
3. Can the network activity of a non-target service be paused for the same window as its process, so that the bottleneck-equivalence property the performance model needs is restored for input/output-bound services?
4. By how much does the extended mechanism improve prediction accuracy compared with the pause-only baseline, and what overhead and limitations come with the improvement?

## 1.6 Significance of the Study

The significance of the study follows from how wide the limitation is. SlowPoke is, at present, the only published system that predicts the throughput effect of possible optimisations in microservice applications without invasive instrumentation and without prior knowledge of the call graph (Xie et al., 2026). Its accuracy, however, is limited to compute-bound services, while the services that engineers most often want to optimise, those bound by database access, caching, and synchronous downstream calls, fall outside its reliable range. By extending causal profiling to input/output-bound services, this study widens the set of optimisation decisions that can be analysed before any implementation work is done. Decisions about query tuning, cache placement, and connection management are brought within reach of the same predictive treatment that is currently available only for computation.

A second contribution is methodological. The cause of the prediction error is examined here through direct kernel measurement rather than inferred from outside behaviour. The use of eBPF instrumentation gives quantitative evidence of input and output that carries on during a pause, which turns an acknowledged but unmeasured limitation into a measured one. This evidence is useful in its own right, because it records a failure mode of distributed causal profiling that has not been characterised before, and it guides the design of any later slowdown mechanism that must account for buffering inside the kernel.

The proposed remedy is, finally, kept deliberately small in its footprint. It depends on standard facilities in the Linux network stack and on the coordination parts that SlowPoke already has, rather than on changes to the kernel or to the application code of the services being profiled. A remedy of this kind can be adopted inside containerised platforms without disruptive change, and its use is not tied to the particular services studied here.

## 1.7 Justification of the Study

The justification for the study rests on three points. The first is that the limitation is real, is documented by the original authors, and is still unaddressed. The suggestion that network bottlenecks be handled through a sidecar or through throttling appears in the discussion of SlowPoke as future work, with no implementation or evaluation attached (Xie et al., 2026). The problem is therefore neither imagined nor already solved.

The second point is that related systems do not close the gap. Critical-path analysis shows where latency is spent in a microservice architecture, but it does not predict the throughput effect of a possible change (Zhang et al., 2022). Latency-distribution modelling rebuilds end-to-end latency from tracing data, which is a different metric from throughput and rests on a different method (Zhang et al., 2023). Resource-management systems that adjust allocations to meet service-level objectives answer a different question again, namely how to size running services rather than how to predict the effect of optimising them (Wang et al., 2024). The original form of causal profiling, from which SlowPoke descends, was limited to a single machine and did not deal with kernel-buffered network activity across hosts (Curtsinger & Berger, 2015). The specific pairing of distributed causal profiling with an input/output-accurate slowdown is therefore missing from the existing literature.

The third point is timeliness. Current microservice deployments lean more and more on synchronous service-to-service communication and on rich interaction with data stores, and both raise the share of services bound by input and output rather than by computation (Huye et al., 2023). A prediction method that keeps its accuracy for such services is, for that reason, of growing rather than shrinking relevance.

## 1.8 Scope

The study is bounded as follows.

Within scope are the following: the characterisation of SlowPoke's prediction error on input/output-bound services through controlled experiments in which synchronous network and database interaction is added to representative services; the validation of the cause through eBPF measurement of leftover input and output during pauses; the design and implementation of a coordinated network-pause mechanism inside SlowPoke's pausing controller; and the evaluation of that mechanism for prediction accuracy, coordination overhead, and sensitivity to input/output intensity.

Outside scope are the following: changes to the Linux kernel or to the meaning of process suspension, since the proposed mechanism stays in user space and uses standard kernel facilities; the treatment of disk input and output, since the proposed network-layer pause does not act on the storage subsystem; formal or analytical proof of the bottleneck-equivalence property under the extended mechanism, since the property is established here by experiment; and revision of SlowPoke's underlying performance model, which is kept unchanged and to which a complementary mechanism is added.

The study assumes that services run under a container-orchestration platform that allows a coordination component to sit beside each service, that pause durations are similar in size to network round-trip times so that the network pause can be lined up with them, and that the interaction of interest is mostly synchronous and network-based.

## 1.9 Thesis Outline

The rest of the thesis is organised as follows.

Chapter 2 reviews the background and related work. The SlowPoke performance model and slowdown mechanism are described in the detail needed to motivate this study, and causal profiling is placed among neighbouring techniques for performance analysis and prediction, including critical-path analysis, latency-distribution modelling, and resource management for service-level objectives.

Chapter 3 identifies and characterises the input/output gap. Controlled experiments are reported in which the prediction error is measured for compute-bound and input/output-bound versions of a representative benchmark, and the relationship between input/output intensity and prediction error is established.

Chapter 4 gives the mechanistic validation. eBPF instrumentation is used to observe the input and output that continues during pauses, and the measured leftover activity is related to the prediction error reported in Chapter 3.

Chapter 5 presents the design and implementation of NetPoke, the coordinated network-pause mechanism. The way it fits into SlowPoke's pausing controller is described, together with the means by which the network pause is lined up with the pause of the process.

Chapter 6 evaluates the mechanism. Prediction accuracy is compared against the baseline on compute-bound and input/output-bound workloads, and the coordination overhead and the sensitivity to workload characteristics are reported.

Chapter 7 discusses the findings, the design trade-offs, and the limitations of the approach, and identifies the cases in which the mechanism is not expected to apply.

Chapter 8 concludes the thesis, restates the contribution, and sets out directions for further work.

---

## References

Chow, M., Meisner, D., Flinn, J., Peek, D., & Wenisch, T. F. (2014). The mystery machine: End-to-end performance analysis of large-scale internet services. In *Proceedings of the 11th USENIX Conference on Operating Systems Design and Implementation (OSDI '14)* (pp. 217–231). USENIX Association.

Curtsinger, C., & Berger, E. D. (2015). Coz: Finding code that counts with causal profiling. In *Proceedings of the 25th Symposium on Operating Systems Principles (SOSP '15)* (pp. 184–197). Association for Computing Machinery.

Gan, Y., Zhang, Y., Cheng, D., Shetty, A., Rathi, P., Katarki, N., Bruno, A., Hu, J., Ritchken, B., Jackson, B., Hu, K., Pancholi, M., He, Y., Clancy, B., Colen, C., Wen, F., Leung, C., Wang, S., Zaruvinsky, L., ... Delimitrou, C. (2019). An open-source benchmark suite for microservices and their hardware-software implications for cloud & edge systems. In *Proceedings of the Twenty-Fourth International Conference on Architectural Support for Programming Languages and Operating Systems (ASPLOS '19)* (pp. 3–18). Association for Computing Machinery.

Gregg, B. (2019). *BPF performance tools: Linux system and application observability*. Addison-Wesley.

Hemminger, S. (2005). Network emulation with NetEm. In *Proceedings of the Australian National Linux Conference (linux.conf.au)*.

Heo, T. (2025). *Control group v2*. Linux kernel documentation. https://docs.kernel.org/admin-guide/cgroup-v2.html

Huye, D., Shkuro, Y., & Sambasivan, R. R. (2023). Lifting the veil on Meta's microservice architecture: Analyses of topology and request workflows. In *2023 USENIX Annual Technical Conference (USENIX ATC '23)* (pp. 419–432). USENIX Association.

Wang, Z., Li, P., Liang, C.-J. M., Wu, F., & Yan, F. Y. (2024). Autothrottle: A practical bi-level approach to resource management for SLO-targeted microservices. In *21st USENIX Symposium on Networked Systems Design and Implementation (NSDI '24)* (pp. 149–165). USENIX Association.

Xie, Y., Jin, D., Çölkesen, O., Kalavri, V., Liagouris, J., & Vasilakis, N. (2026). Slowpoke: End-to-end throughput optimization modeling for microservice applications. In *Proceedings of the 23rd USENIX Symposium on Networked Systems Design and Implementation (NSDI '26)*. USENIX Association.

Zhang, Y., Isaacs, R., Yue, Y., Yang, J., Zhang, L., & Vigfusson, Y. (2023). LatenSeer: Causal modeling of end-to-end latency distributions by harnessing distributed tracing. In *Proceedings of the 2023 ACM Symposium on Cloud Computing (SoCC '23)* (pp. 502–519). Association for Computing Machinery.

Zhang, Z., Ramanathan, M. K., Raj, P., Parwal, A., Sherwood, T., & Chabbi, M. (2022). CRISP: Critical path analysis of large-scale microservice architectures. In *2022 USENIX Annual Technical Conference (USENIX ATC '22)* (pp. 655–672). USENIX Association.
