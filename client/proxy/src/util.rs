use async_trait::async_trait;
use bytes::Bytes;
use hyper::{Body, Request, Response};
use std::convert::Infallible;

thread_local! {
    pub static GCLIENT: hyper::Client<hyper::client::HttpConnector, hyper::Body> = hyper::Client::new();
}

#[async_trait]
pub trait Backend {
    async fn prepare(&self);

    async fn run(_req: Request<Body>) -> Result<Response<Body>, Infallible>;
}

pub async fn send_req(ip: &str, method: &str, req: String) -> Bytes {
    let url = "http://".to_owned() + ip + "/" + method;
    let r = hyper::Request::builder()
        .method(hyper::Method::POST)
        .uri(url)
        .header("content-type", "application/json")
        .header("Connection", "close")
        .body(hyper::Body::from(req))
        .unwrap();
    let client = GCLIENT.with(|c| c.clone());
    // Timeout must be LONGER than the maximum sch_plug hold duration so the
    // proxy worker waits for the buffered response to arrive after net_release()
    // rather than timing out and dropping the request. Dropping requests during
    // a plug hold corrupts the slowdown throughput measurement S, which breaks
    // the prediction formula. At batch=100 / ~40 req/s the hold is ~2.5s;
    // 10s gives a safe margin while still bounding hangs if the service crashes.
    let resp = match tokio::time::timeout(
        std::time::Duration::from_secs(10),
        client.request(r),
    ).await {
        Ok(Ok(r)) => r,
        _ => return Bytes::new(),
    };
    hyper::body::to_bytes(resp.into_body()).await.unwrap_or_default()
}

// How to do it elegantly?
#[macro_export]
macro_rules! impl_backend {
    ($($app:ident),*) => {
        impl App {
            async fn prepare(&self) {
                match self {
                    $(
                        App::$app(inner) => inner.prepare().await,
                    )*
                }
            }

            async fn run(&self) {
                match self {
                    $(
                        App::$app(_inner) => {
                            let addr = std::net::SocketAddr::from(([127, 0, 0, 1], 3000));
                            let make_svc =
                                make_service_fn(|_conn| async { Ok::<_, Infallible>(service_fn($app::run)) });
                            let server = Server::bind(&addr).serve(make_svc);
                            server.await.unwrap();
                        }
                    )*
                }
            }
        }
    };
}
