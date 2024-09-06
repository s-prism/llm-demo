### To run the llm demo

#### Requirements:

npm must be installed
Node version must be 12.0.0 or above

#### The commands:
```npm install``` installs all packages required to run the demo
```elm make src/Main.elm --output elm.js``` compiles the Elm frontend code to JavaScript, to be used as a script for the frontend html file
```rm -rf .parcel-cache``` only required if this has been run before. clears the cache of the 'parcel' build tool 
```PARCEL_ELM_NO_DEBUG=1 npx parcel ./index.html --port $CLIENT_PORT_NUMBER``` opens the browser-side client on the specified port