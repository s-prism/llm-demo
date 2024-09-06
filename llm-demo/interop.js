import {Elm} from "./src/Main.elm";

var app = Elm.Main.init({
    node: document.getElementById("page")
});

var chat_history = [{role : "system", content: "You are an AI assistant."}];
var response_buffer = "";

async function createResponse(chat_history){ 
    response_buffer = "";
    fetch("http://localhost:8000/api/chatcompletion", {
        method: "POST",
        body: JSON.stringify({
            model: "gpt-3.5-turbo",
            messages: chat_history,
            stream: true
        }),
        headers: {
        }
      });
}

//receives data-only server sent events from the api's buffer, and returns the token contents to the browser
function processResponse(eventData, buffer) {
    var data = eventData;
    if (buffer != "") {
        data = buffer + data;
    }
    //split buffered events by event
    //first "event" is removed as it is empty (one split occurs before the first "data: ")
    //and the events are data-only events
    var responseList = data.split("data: ").slice(1);

    for (let r = 0; r < responseList.length; r++){
        if (responseList[r].slice(-2) == "\n\n") {
            responseList[r] = responseList[r].slice(0,-2);
        }

        if (responseList[r] == "[DONE]") { 
            //response is now complete
            addToAssistantChatHistory(response_buffer);
            response_buffer = "";
            app.ports.messageReceiver.send({"done":true, "content": ""});
        }
        else if (responseList[r].slice(-3) == "}]}") {
            app.ports.messageReceiver.send({"done":false, "content": JSON.parse(responseList[r]).choices[0].delta.content});
        }
        else if (r == responseList.length - 1) { 
            //only part of the last response token was sent
            return responseList[r];
        } 
    } 
    return "";
}

var response_buffer = "";

let events = new EventSource("http://localhost:8000/events");
events.onmessage = (event) => {
    response_buffer = processResponse(event.data, response_buffer);
}

function addToUserChatHistory(content){
    chat_history.push({role: "user", content: content});
}
function addToAssistantChatHistory(content){
    chat_history.push({role: "assistant", content: content});
}


app.ports.sendMessage.subscribe(async function(message) {
    addToUserChatHistory(message)
    
    createResponse(chat_history);
});
