Kwame Nkrumah University of Science and Technology, Kumasi, Ghana
Department of Computer Science

I/O-Aware Causal Profiling for Throughput Prediction in Microservice Systems

(NetPoke: Network-Aware Throughput Prediction for Microservice Applications)

A Thesis Submitted in Partial Fulfilment of the Requirements for the Degree of Master of Philosophy in Computer Science

Author: Afram Visca Gyebi
Supervisor: Dr. (Mrs.) Rose-Mary Mensah Gyening

---

# Chapter 1: Introduction

## 1.1 Introduction

Large-scale online applications are now assembled, for the most part, from collections of small and independently deployable services that interact over a network. Each service is owned by a small team, released on its own schedule, and scaled according to its own demand. The pattern is attractive because it decouples development and deployment, yet the same decoupling makes the performance of the application as a whole difficult to reason about. A request that appears simple to an end user is often served by a chain or a fan-out of internal calls, and the time spent in any single service is shaped by queueing, contention, and synchronisation effects that are not visible from the outside (Chow et al., 2014). The scale at which such systems operate has been documented in industrial studies, where individual products are reported to depend on thousands of interacting services with deep and irregular call graphs (Huye et al., 2023).

A recurring and consequential question is faced by the engineers who operate these systems. Given a fixed budget for optimisation work, which service should be improved so that the throughput of the whole application rises by the largest amount? The question is harder than it first appears. Because services are coupled through shared resources and request dependencies, an improvement to one service does not translate into a proportional improvement at the application boundary. Effort can be spent optimising a service that is not on the critical path, in which case the measured benefit is negligible and the bottleneck simply re-emerges elsewhere. What is required, before any code is changed, is a principled means of predicting the end-to-end effect of a hypothetical optimisation.

This style of prediction has its roots in causal profiling, a technique introduced for single-machine multithreaded programs by Curtsinger and Berger (2015). The central idea is counter-intuitive but powerful. Rather than speeding up a region of code, which cannot be done without first writing the optimisation, the profiler slows down everything else by a controlled amount. The relative relationships between components are preserved under this transformation, so the measured behaviour of the artificially slowed execution reveals what the genuinely optimised execution would have achieved. The approach has been carried into the distributed setting by Xie et al. (2026), whose system, SlowPoke, predicts throughput improvements for microservice applications without requiring distributed tracing or prior knowledge of the call graph. Across four real-world applications, SlowPoke was reported to predict optimisation effects with a root mean squared error of 2.07%, a level of accuracy that establishes causal profiling as a credible planning tool for distributed services.

A limitation of the mechanism on which SlowPoke depends is the concern of the present study. The slowdown is realised by pausing the operating-system processes of non-target services with the POSIX signal SIGSTOP, and by resuming them later with SIGCONT (Xie et al., 2026). Process suspension removes time from the central processing unit, which is exactly the resource that limits a compute-bound service. It does not, however, suspend the activity that the kernel performs on behalf of a service. While a process is frozen, network packets continue to be received into socket buffers, acknowledgements continue to be emitted, and pending input and output operations continue to drain inside the kernel. For a service whose throughput is governed by network or database interaction rather than by computation, the pause therefore fails to slow the resource that actually matters. The consequence is that the artificial slowdown is incomplete, the condition the performance model relies upon is no longer satisfied, and the resulting prediction is distorted.

The distinction between compute-bound and input/output-bound services is not a marginal one. A large share of services in production perform database queries, cache lookups, and synchronous calls to downstream dependencies, and for those services the limiting resource is rarely the processor (Huye et al., 2023). A prediction method that is accurate only when the processor is the bottleneck is therefore restricted to a minority of realistic cases. Extending causal profiling so that it remains accurate for input/output-bound services is the problem addressed by this thesis, and the proposed extension, named NetPoke, is the contribution that follows.

## 1.2 Problem Statement

The accuracy of SlowPoke rests on a single assumption. When a non-target service is paused, the paused execution is assumed to be equivalent, with respect to the application bottleneck, to an execution in which that service had been genuinely slowed. For a compute-bound service the assumption holds, because suspending the process withdraws processor time in direct proportion to the length of the pause, and processor time is the resource that constrains the service.

The assumption is violated when the limiting resource is input and output rather than computation. Suspension with SIGSTOP halts only the user-space execution of the process. The kernel continues to act on the service's open connections during the pause window: incoming segments are accepted into receive buffers, the transport layer continues to acknowledge them, and outstanding requests to downstream services or to storage continue towards completion. When the process is resumed, the work that accumulated during the pause is consumed in a short burst. The effective reduction in the service's input/output capacity is therefore far smaller than the duration of the pause would suggest, and the slowdown that the performance model believes it has applied has not, in fact, been applied. Because the bottleneck is no longer preserved, the throughput measured under slowdown no longer corresponds to the throughput that the optimised system would have sustained, and the prediction is degraded.

The magnitude of the distortion is governed by the quantity of input and output that is in flight at the moment of suspension. Where little synchronous interaction is present, the residual activity is small and the error remains modest. Where a service issues blocking database queries, depends on synchronous calls to other services, or otherwise spends most of its time waiting on the network, the residual activity is substantial, and the predicted throughput diverges from the ground truth. The systematic direction of the error is over-prediction, because the slowed system retains more capacity than the model accounts for, and the optimised throughput is therefore estimated to be higher than it truly is.

The limitation is acknowledged, though not measured, by the authors of SlowPoke. It is stated that the mechanism preserves general processor-time bottlenecks but does not accurately preserve network or disk bottlenecks, because such bottlenecks involve extensive buffering and caching inside the kernel (Xie et al., 2026). The same work suggests, as a direction for future investigation, that network bottlenecks might be addressed through a service-mesh sidecar or through input/output throttling, but no such mechanism is designed, implemented, or evaluated there. A gap consequently exists between the demonstrated promise of distributed causal profiling and its applicability to the input/output-bound services that dominate modern deployments. Closing that gap, by quantifying the error, by establishing its cause through direct kernel measurement, and by extending the slowdown mechanism so that the pause becomes complete across resources, is the problem that this study sets out to solve.

## 1.3 Aim

The aim of this study is to design, implement, and evaluate an input/output-aware extension to SlowPoke's slowdown mechanism that preserves the bottleneck-equivalence property for network-bound microservices, thereby restoring throughput-prediction accuracy for those services to the level that SlowPoke already achieves for compute-bound services.

## 1.4 Objectives

The aim is pursued through four objectives:

1. To quantify the throughput-prediction error introduced by SlowPoke's suspension-only slowdown when it is applied to input/output-bound services, and to determine how that error varies with the intensity of the input and output performed.
2. To establish the cause of the error through direct kernel-level measurement, using extended Berkeley Packet Filter (eBPF) instrumentation to observe and quantify the residual input and output that proceeds during suspension windows, and to relate that residual activity to the observed prediction error.
3. To design and implement an extended slowdown mechanism that, in coordination with the existing pausing controller, suspends a service's network activity for the same window in which its process is suspended, so that the pause is complete across both processor and network resources.
4. To evaluate the extended mechanism against the SlowPoke baseline across compute-bound and input/output-bound workloads, reporting the improvement in prediction accuracy together with the coordination overhead and the conditions under which the mechanism is and is not applicable.

## 1.5 Research Questions

The study is organised around four research questions, each corresponding to one of the objectives above:

1. How large is the throughput-prediction error that SlowPoke's suspension-only slowdown produces for input/output-bound services, and how does that error scale with input and output intensity and with pause duration?
2. Can the residual input and output that occurs during suspension windows be measured directly at the kernel, and does the quantity of residual activity account for the observed prediction error?
3. Can the network activity of a non-target service be suspended for the same window as its process, so that the bottleneck-equivalence property required by the performance model is restored for input/output-bound services?
4. To what extent does the extended mechanism improve prediction accuracy relative to the suspension-only baseline, and what overhead and limitations accompany the improvement?

## 1.6 Significance of the Study

The significance of the study follows from the scope of the limitation it addresses. SlowPoke is, at present, the only published system that predicts the throughput effect of hypothetical optimisations in microservice applications without invasive instrumentation or prior knowledge of the call graph (Xie et al., 2026). Its accuracy, however, is confined to compute-bound services, while the services that practitioners most often wish to optimise, those bound by database access, caching, and synchronous downstream calls, lie outside its reliable operating envelope. By extending causal profiling to input/output-bound services, this study widens the class of optimisation decisions that can be analysed before any implementation effort is committed. Decisions concerning query tuning, cache placement, and connection management become amenable to the same predictive treatment that is currently available only for computation.

A second contribution is methodological. The cause of the prediction error is examined here through direct kernel measurement rather than inferred from external behaviour. The use of eBPF instrumentation provides quantitative evidence of input and output that continues during suspension, which converts an acknowledged but unquantified limitation into a measured phenomenon. This evidence is of independent value, since it documents a failure mode of distributed causal profiling that has not previously been characterised, and it informs the design of any future slowdown mechanism that must account for kernel-level buffering.

The proposed remedy is, finally, deliberately modest in its footprint. It depends on standard facilities provided by the Linux network stack and on the existing coordination infrastructure of SlowPoke, rather than on modifications to the kernel or to the application code of the services being profiled. A remedy with this property can be adopted within containerised orchestration platforms without disruptive change, and its applicability is not confined to the particular services examined in this work.

## 1.7 Justification of the Study

The justification for undertaking the study rests on three considerations. The first is that the limitation is real, is documented by the original authors, and remains unaddressed. The proposal that network bottlenecks be handled through a sidecar or through throttling appears in the discussion of SlowPoke as future work, and no implementation or evaluation accompanies it (Xie et al., 2026). The problem is therefore neither speculative nor already solved.

The second consideration is that related systems do not close the gap. Critical-path analysis identifies where latency is incurred in a microservice architecture but does not predict the throughput consequence of a hypothetical change (Zhang et al., 2022). Latency-distribution modelling reconstructs end-to-end latency from tracing data, which is a different metric from throughput and rests on a different methodology (Zhang et al., 2023). Resource-management systems that adjust allocations to meet service-level objectives operate on a different question again, namely how to size running services rather than how to predict the effect of optimising them (Wang et al., 2024). The original formulation of causal profiling, from which SlowPoke descends, was confined to a single machine and did not contend with kernel-buffered network activity across hosts (Curtsinger & Berger, 2015). The specific combination of distributed causal profiling with an input/output-accurate slowdown is therefore absent from the existing literature.

The third consideration is timeliness. Contemporary microservice deployments increasingly favour synchronous service-to-service communication and rich interaction with data stores, both of which increase the proportion of services that are bound by input and output rather than by computation (Huye et al., 2023). A prediction method that retains its accuracy for such services is consequently of growing rather than diminishing relevance.

## 1.8 Scope

The study is delimited as follows.

Within scope are: the characterisation of SlowPoke's prediction error on input/output-bound services through controlled experiments in which synchronous network and database interaction is introduced into representative services; the mechanistic validation of the cause through eBPF measurement of residual input and output during suspension; the design and implementation of a coordinated network-suspension mechanism within SlowPoke's pausing controller; and the evaluation of that mechanism with respect to prediction accuracy, coordination overhead, and sensitivity to input/output intensity.

Outside scope are: modification of the Linux kernel or of the semantics of process suspension, since the proposed mechanism is confined to user space and to standard kernel facilities; the treatment of disk input and output, since the proposed network-layer suspension does not act on the storage subsystem; formal or analytical proof of the bottleneck-equivalence property under the extended mechanism, since the property is established here empirically; and revision of SlowPoke's underlying performance model, which is retained without alteration and to which a complementary mechanism is added.

The study assumes that services are deployed under a container-orchestration platform that permits a coordination component to be co-located with each service, that pause durations are comparable in magnitude to network round-trip times so that network suspension can be aligned with them, and that the interaction of interest is predominantly synchronous and network-based.

## 1.9 Thesis Outline

The remainder of the thesis is organised as follows.

Chapter 2 reviews the background and related work. The SlowPoke performance model and slowdown mechanism are described in the detail required to motivate the present study, and causal profiling is situated among neighbouring techniques for performance analysis and prediction, including critical-path analysis, latency-distribution modelling, and resource management for service-level objectives.

Chapter 3 identifies and characterises the input/output gap. Controlled experiments are reported in which the prediction error is measured for compute-bound and input/output-bound configurations of a representative benchmark, and the relationship between input/output intensity and prediction error is established.

Chapter 4 provides the mechanistic validation. eBPF instrumentation is used to observe the input and output that proceeds during suspension windows, and the measured residual activity is related to the prediction error reported in Chapter 3.

Chapter 5 presents the design and implementation of NetPoke, the coordinated network-suspension mechanism. The integration with SlowPoke's pausing controller is described, together with the means by which network suspension is aligned with the suspension of the process.

Chapter 6 evaluates the mechanism. Prediction accuracy is compared against the baseline across compute-bound and input/output-bound workloads, and the coordination overhead and sensitivity to workload characteristics are reported.

Chapter 7 discusses the findings, the design trade-offs, and the limitations of the approach, and identifies the conditions under which the mechanism is not expected to apply.

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
