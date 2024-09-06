mod broadcast;
mod handler;

use actix_cors::Cors;
use actix_web::http;
use actix_web::{middleware::Logger, web, App, HttpResponse, HttpServer, Responder};
use actix_web_lab::extract::Path;
use clap::Parser;
use log::info;
use std::{env, sync::Arc, u16};

#[derive(Parser)]
#[command(version, about, long_about = None)]
struct Args {
    // Server port number
    #[arg(short, long)]
    port: u16,
}

pub struct AppState {
    broadcaster: Arc<broadcast::Broadcaster>,
}

// SSE
pub async fn sse_client(state: web::Data<AppState>) -> impl Responder {
    state.broadcaster.new_client().await
}

pub async fn broadcast_msg(
    state: web::Data<AppState>,
    Path((msg,)): Path<(String,)>,
) -> impl Responder {
    state.broadcaster.broadcast(&msg).await;
    info!("Broadcast msg sent: {}", &msg);
    HttpResponse::Ok().body("msg sent")
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init();
    let args = Args::parse();

    if env::var_os("RUST_LOG").is_none() {
        env::set_var("RUST_LOG", "actix_web=info");
    }
    let broadcaster = broadcast::Broadcaster::create();

    HttpServer::new(move || {
        let cors = Cors::default()
            .allow_any_origin()
            .allowed_methods(vec!["POST"])
            .allowed_headers(vec![
                http::header::AUTHORIZATION,
                http::header::ACCEPT,
                http::header::ACCESS_CONTROL_ALLOW_ORIGIN,
            ])
            .allowed_header(http::header::CONTENT_TYPE)
            .supports_credentials();
        App::new()
            .app_data(web::Data::new(AppState {
                broadcaster: Arc::clone(&broadcaster),
            }))
            // This route is used to listen to events/ sse events
            .route("/events{_:/?}", web::get().to(sse_client))
            // This route will create a notification
            .route("/events/{msg}", web::get().to(broadcast_msg))
            .configure(handler::config)
            .wrap(cors)
            .wrap(Logger::default())
    })
    .bind(("localhost", args.port))?
    .run()
    .await
}
