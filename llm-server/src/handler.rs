use crate::AppState;
use actix_web::{post, web, HttpResponse, Responder};
use dotenv;
use futures::stream::StreamExt;
use log::{error, info, trace, warn};
use reqwest;
use std::env;

//send request to openai and await response
//return openai's chat response
#[post("/chatcompletion")]
async fn chat_completion_handler(
    body: std::string::String,
    state: web::Data<AppState>,
) -> impl Responder {
    let mut api_key = String::new();

    dotenv::dotenv().ok();

    for (key, value) in env::vars() {
        trace!("key: {}, value: {}", key, value);
        if key == "OPENAI_API_KEY" {
            api_key = value;
            info!("api key set");
        }
    }
    if api_key == String::new() {
        error!("No openai api key found under the environment variable OPENAI_API_KEY")
    }

    let url = "https://api.openai.com/v1/chat/completions";
    let client = reqwest::Client::new();
    let res = client
        .post(url)
        .body(body)
        .header("Content-Type", "application/json")
        .bearer_auth(api_key)
        .send()
        .await;

    let mut stream = res.expect("Error! Reason: ").bytes_stream();
    while let Some(item) = stream.next().await {
        match item {
            Ok(v) => {
                info!("Streamed response is valid");
                match std::str::from_utf8(&v) {
                    Ok(w) => {
                        info!("Conversion of stream type from bytes to string was successful");
                        state.broadcaster.broadcast(&w).await;
                    }
                    Err(e) => warn!("Conversion of stream type from bytes to string was unsuccessful. Error message: {}", e),
                }
            }
            Err(e) => warn!("Streamed response is invalid. Error message: {}", e),
        }
    }
    HttpResponse::Ok().body("ok")
}

pub fn config(conf: &mut web::ServiceConfig) {
    let scope = web::scope("/api").service(chat_completion_handler);

    conf.service(scope);
}
