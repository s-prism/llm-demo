port module Main exposing (..)

import Browser
import Browser.Dom exposing (Viewport, getViewport, setViewport)
import Browser.Events
import Element exposing (alignBottom, centerX, centerY, layout, padding, px, rgb255, spacing, width, wrappedRow)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input exposing (labelHidden)
import Html exposing (Html, div, hr, img, pre)
import Html.Attributes exposing (src)
import Html.Events
import Json.Decode as Decode exposing (map2)
import Json.Encode as Encode
import List
import String
import Task
import Time exposing (posixToMillis)


port sendMessage : String -> Cmd msg


port messageReceiver : (Encode.Value -> msg) -> Sub msg



--MAIN


main : Program () Model Msg
main =
    Browser.document { init = init, view = view, update = update, subscriptions = subscriptions }



--MODEL + initialisation


type alias Model =
    { user_text : String
    , response : String
    , chat_history : List { role : Roles, content : String }
    , response_field : String
    , width : Int
    , height : Int
    , timeOfRequest : Int
    , numOfTokens : Maybe Int
    , tokensPerSecond : Float
    , timeToFirstToken : Int
    , runTime : Int
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { user_text = ""
      , response = ""
      , chat_history = []
      , response_field = ""
      , width = 100
      , height = 100
      , timeOfRequest = 0
      , numOfTokens = Nothing
      , tokensPerSecond = 0
      , timeToFirstToken = 0
      , runTime = 0
      }
    , Cmd.batch [ sendMessage "", viewportFinder ]
    )


type Roles
    = User
    | Assistant



--UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        --change in what the user has entered
        Change newContent ->
            ( { model | user_text = newContent }, Cmd.none )

        --finding the keyCode of what the user has entered, to check whether they pressed Enter
        Key keyCode ->
            if keyCode == 13 then
                update Enter model

            else
                ( model, Cmd.none )

        --starts generating a response & metrics after the user presses enter
        Enter ->
            ( { model
                | response = ""
                , chat_history = { role = User, content = model.user_text } :: model.chat_history
                , response_field = ""
              }
                |> wipeMetrics
            , Cmd.batch [ Task.perform (\time -> NewToken { done = False, time = time }) Time.now, sendMessage model.user_text ]
            )

        --one token of the LLM's response (or a DONE indicator) is received
        Responded (Ok decoded) ->
            --LLM's streamed response is completed
            if decoded.done == True then
                ( { model
                    | chat_history = { role = Assistant, content = model.response } :: model.chat_history
                    , response = ""
                    , response_field = ""
                  }
                , Task.perform (\time -> NewToken { done = True, time = time }) Time.now
                )
                --LLM has sent a token (streamed response is not yet complete)

            else
                ( { model
                    | user_text = ""
                    , response = model.response ++ decoded.content
                    , response_field = model.response_field ++ decoded.content
                  }
                , Task.perform (\time -> NewToken { done = False, time = time }) Time.now
                )

        --issue with response that the LLM has sent
        Responded (Err _) ->
            ( model, Cmd.none )

        --current time found
        NewToken { done, time } ->
            if done == False then
                case model.numOfTokens of
                    Nothing ->
                        --tokens set to 0 as first "response token" is an empty string, which is not counted as a token
                        ( { model | timeOfRequest = posixToMillis time, numOfTokens = Just 0 }
                        , Cmd.none
                        )

                    Just 0 ->
                        ( { model | timeToFirstToken = posixToMillis time - model.timeOfRequest, numOfTokens = Just 1 }
                        , Cmd.none
                        )

                    Just k ->
                        ( { model
                            | numOfTokens = Just (k + 1)
                            , tokensPerSecond = getTokensPerSecond (k + 1) (posixToMillis time - model.timeToFirstToken - model.timeOfRequest)
                          }
                        , Task.perform (\_ -> ResetFail) (setViewport 0 (toFloat model.height))
                        )

            else
                ( { model
                    | runTime = posixToMillis time - model.timeOfRequest - model.timeToFirstToken
                    , numOfTokens = increment model.numOfTokens
                    , tokensPerSecond = getTokensPerSecond (getRaw model.numOfTokens) (posixToMillis time - model.timeToFirstToken - model.timeOfRequest)
                  }
                , Task.perform (\_ -> ResetFail) (setViewport 0 (toFloat model.height))
                )

        --dimensions of page are updated when changed. The height is used to autoscroll to the bottom of the conversation
        Dim w h ->
            ( { model | width = w - 10, height = h - 100 }, Cmd.none )

        ResetFail ->
            ( model, Cmd.none )


type Msg
    = Change String
    | Key Int
    | Enter
    | Responded (Result Decode.Error ResponsePart)
    | NewToken { done : Bool, time : Time.Posix }
    | Dim Int Int
    | ResetFail


type alias ResponsePart =
    { done : Bool, content : String }


decodeResponse : Decode.Decoder ResponsePart
decodeResponse =
    map2 ResponsePart (Decode.field "done" Decode.bool) (Decode.field "content" Decode.string)


onKeyUp : (Int -> msg) -> Html.Attribute msg
onKeyUp tagger =
    Html.Events.on "keyup" (Decode.map tagger Html.Events.keyCode)


viewportFinder : Cmd Msg
viewportFinder =
    Task.attempt viewResult getViewport


viewResult : Result error Viewport -> Msg
viewResult result =
    case result of
        Ok vp ->
            Dim (truncate vp.viewport.width) (truncate vp.viewport.height)

        Err _ ->
            Dim 0 0


wipeMetrics : Model -> Model
wipeMetrics model =
    { model
        | timeOfRequest = 0
        , numOfTokens = Nothing
        , tokensPerSecond = 0
        , timeToFirstToken = 0
        , runTime = 0
    }


getTokensPerSecond : Int -> Int -> Float
getTokensPerSecond numOfTokens time =
    toFloat numOfTokens / (toFloat time / 1000)


increment : Maybe Int -> Maybe Int
increment numOfTokens =
    case numOfTokens of
        Nothing ->
            Just 0

        Just k ->
            Just (k + 1)


getRaw : Maybe Int -> Int
getRaw numOfTokens =
    case numOfTokens of
        Nothing ->
            -1

        Just k ->
            k



--SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch [ messageReceiver (Decode.decodeValue decodeResponse >> Responded), Browser.Events.onResize (\w h -> Dim w h) ]



--VIEW


view : Model -> Document Msg
view model =
    { title = "LLM Demo"
    , body =
        [ Html.table []
            [ Html.thead [ Html.Attributes.height (truncate (toFloat model.height * 3 / 4)) ] (arrangeElements model)
            , Html.tr []
                [ layout []
                    (wrappedRow [ centerX, centerY, Font.size 16 ]
                        [ secToFirstToken model.timeToFirstToken
                        , Element.text " sec to first token | "
                        , tokensPerSecond model.tokensPerSecond
                        , Element.text " tokens / sec | "
                        , tokens (getRaw model.numOfTokens)
                        , Element.text " tokens | "
                        , runTime model.runTime
                        , Element.text " sec run time"
                        ]
                    )
                ]
            , div [] [ userRow model.user_text ]
            ]
        ]
    }


type alias Document msg =
    { title : String
    , body : List (Html msg)
    }


arrangeElements : Model -> List (Html Msg)
arrangeElements model =
    [ img [ src "https://www.achronix.com/sites/default/files/logo.png" ] []
    , hr [] []
    , Html.h1 [] [ layout [] (Element.text " LLM Demo") ]
    , div [] []
    , historyToDisplay model.chat_history
    , div [ widthAttr model.width ]
        [ layout []
            (if model.response_field == "" then
                Element.text ""

             else
                Element.table [ Font.size 16 ]
                    { data = [ { role = Assistant, content = model.response_field } ]
                    , columns =
                        [ { header = Element.text ""
                          , width = Element.fillPortion 1
                          , view = \block -> userBlock block.role
                          }
                        , { header = Element.text ""
                          , width = Element.fillPortion 9
                          , view = \block -> contentBlock block.content block.role
                          }
                        ]
                    }
            )
        ]
    , pre [] [ Html.text "\n" ]
    ]


historyToDisplay : List { role : Roles, content : String } -> Html Msg
historyToDisplay chat_history =
    layout []
        (Element.table [ Font.size 16 ]
            { data = List.reverse chat_history
            , columns =
                [ { header = Element.text ""
                  , width = Element.fillPortion 1
                  , view = \block -> userBlock block.role
                  }
                , { header = Element.text ""
                  , width = Element.fillPortion 9
                  , view = \block -> contentBlock block.content block.role
                  }
                ]
            }
        )


contentBlock : String -> Roles -> Element.Element Msg
contentBlock response role =
    wrappedRow []
        [ Element.paragraph
            [ if role == Assistant then
                Background.color (rgb255 230 230 230)

              else
                Background.color (rgb255 255 255 255)
            , Border.color (rgb255 255 255 255)
            , Border.rounded 10
            , padding 7
            , centerY
            ]
            (List.map Element.text (String.split "\n" response)
                |> List.intersperse (Element.html <| pre [] [])
            )
        ]


userBlock : Roles -> Element.Element msg
userBlock role =
    let
        strRole =
            if role == User then
                "user"

            else
                "assistant"
    in
    wrappedRow []
        [ Element.el [ padding 7, centerY, Element.alignTop ]
            (Element.text (strRole ++ ": "))
        ]


widthAttr : Int -> Html.Attribute msg
widthAttr width =
    Html.Attributes.style "width" (String.fromInt width ++ "px")


secToFirstToken : Int -> Element.Element msg
secToFirstToken time =
    Element.text
        (if time == 0 then
            "   "

         else
            toFloat time / 1000 |> String.fromFloat
        )


tokensPerSecond : Float -> Element.Element msg
tokensPerSecond tps =
    Element.text
        (if tps == 0 then
            "   "

         else
            tps |> String.fromFloat |> String.left 5
        )


tokens : Int -> Element.Element msg
tokens numOfTokens =
    Element.text
        (if numOfTokens <= 0 then
            "   "

         else
            numOfTokens |> String.fromInt
        )


runTime : Int -> Element.Element msg
runTime rt =
    Element.text
        (if rt == 0 then
            "   "

         else
            toFloat rt / 1000 |> String.fromFloat
        )


enterButton : Element.Element Msg
enterButton =
    Element.Input.button
        [ padding 15
        , Border.rounded 10
        , Background.color (rgb255 200 200 200)
        , Element.mouseOver
            [ Background.color (rgb255 138 138 138) ]
        , Element.focused
            [ Background.color (rgb255 138 138 138) ]
        ]
        { onPress = Just Enter, label = Element.text "Chat" }


elementOnKeyUp : (Int -> msg) -> Element.Attribute msg
elementOnKeyUp tagger =
    Element.htmlAttribute (onKeyUp tagger)


textField : String -> Element.Element Msg
textField content =
    Element.Input.text
        [ width (px 400)
        , padding 15
        , Border.rounded 10
        , centerX
        , centerY
        , elementOnKeyUp Key
        ]
        { onChange = Change
        , label = labelHidden "Enter something here"
        , placeholder =
            Just
                (Element.Input.placeholder []
                    (Element.text "Enter something here")
                )
        , text = content
        }


userRow : String -> Html Msg
userRow user_text =
    layout []
        (wrappedRow [ padding 10, spacing 10, alignBottom, centerX, centerY, Font.size 16 ]
            [ textField user_text, enterButton ]
        )
