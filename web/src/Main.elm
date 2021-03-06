module Main exposing (main)

import Regex exposing (..)
import Html exposing (..)
import Http
import Navigation
import Route
import Task
import Models.Talk exposing (Talk, talkDecoder)
import Ports
import HomePage
import TalkPage
import SearchPage
import NotFoundPage
import ErrorPage
import Components.Header.Header as Header
import Components.Footer.Footer as Footer
import Components.Loading.Loading as Loading


main =
    Navigation.program UrlChange
        { init = init, view = view, update = update, subscriptions = subscriptions }


type Page
    = Blank
    | NotFound
    | Errored
    | Home HomePage.Model
    | Talk TalkPage.Model
    | Search SearchPage.Model


type PageStatus
    = RedirectFrom Page
    | Loaded Page


type alias Model =
    { pageStatus : PageStatus
    }


getPage : PageStatus -> Page
getPage pageStatus =
    case pageStatus of
        RedirectFrom page ->
            page

        Loaded page ->
            page


init : Navigation.Location -> ( Model, Cmd Msg )
init loc =
    setRoute loc <| Model (Loaded Blank)


redirectToTalkPage : Model -> String -> ( Model, Cmd Msg )
redirectToTalkPage model slug =
    ( model, Navigation.newUrl ("/talks/" ++ slug) )


setRoute : Navigation.Location -> Model -> ( Model, Cmd Msg )
setRoute loc model =
    let
        redirectTo toMsg req =
            ( { model | pageStatus = RedirectFrom (getPage model.pageStatus) }
            , Task.attempt toMsg req
            )
    in
        case Route.fromLocation loc of
            Just Route.Home ->
                redirectTo HomeLoaded (HomePage.init)

            Just (Route.Talk slug) ->
                redirectTo TalkLoaded (TalkPage.init slug)

            Just (Route.Search q) ->
                case q of
                    Just query ->
                        let
                            matches =
                                find (AtMost 1)
                                    (regex "^https?://www.ted.com/talks/(\\w+)")
                                    query
                        in
                            case (List.map .submatches matches) of
                                ((Just slug) :: _) :: _ ->
                                    redirectToTalkPage model slug

                                _ ->
                                    redirectTo SearchLoaded (SearchPage.init query)

                    Nothing ->
                        ( { model | pageStatus = Loaded NotFound }
                        , Ports.setTitle NotFoundPage.title
                        )

            Nothing ->
                ( { model | pageStatus = Loaded NotFound }, Ports.setTitle NotFoundPage.title )


type Msg
    = UrlChange Navigation.Location
    | HomeLoaded (Result Http.Error HomePage.Model)
    | TalkLoaded (Result Http.Error TalkPage.Model)
    | SearchLoaded (Result Http.Error SearchPage.Model)
    | HomeMsg HomePage.Msg
    | TalkMsg TalkPage.Msg
    | SearchMsg SearchPage.Msg
    | HeaderMsg Header.Msg
    | FooterMsg Footer.Msg
    | RandomTalkResult (Result Http.Error Talk)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        toPage toModel toMsg subUpdate subMsg subModel =
            let
                ( newModel, newCmd ) =
                    subUpdate subMsg subModel
            in
                ( { model | pageStatus = Loaded (toModel newModel) }, Cmd.map toMsg newCmd )

        toError err =
            case err of
                Http.BadStatus res ->
                    case res.status.code of
                        404 ->
                            ( { model | pageStatus = Loaded NotFound }, Ports.setTitle NotFoundPage.title )

                        _ ->
                            ( { model | pageStatus = Loaded Errored }, Ports.setTitle ErrorPage.title )

                _ ->
                    ( { model | pageStatus = Loaded Errored }, Ports.setTitle ErrorPage.title )
    in
        case ( msg, model.pageStatus ) of
            ( UrlChange loc, _ ) ->
                setRoute loc model

            ( HomeMsg (HomePage.RouteTo route), _ ) ->
                ( model, Navigation.newUrl <| Route.toString route )

            ( TalkMsg (TalkPage.RouteTo route), _ ) ->
                ( model, Navigation.newUrl <| Route.toString route )

            ( TalkMsg msg, Loaded (Talk submodel) ) ->
                toPage Talk TalkMsg TalkPage.update msg submodel

            ( TalkMsg msg, _ ) ->
                ( model, Cmd.none )

            ( SearchMsg (SearchPage.RouteTo route), _ ) ->
                ( model, Navigation.newUrl <| Route.toString route )

            ( HomeLoaded (Ok submodel), _ ) ->
                ( { model | pageStatus = Loaded (Home submodel) }, Cmd.none )

            ( HomeLoaded (Err err), _ ) ->
                toError err

            ( TalkLoaded (Ok submodel), _ ) ->
                ( { model | pageStatus = Loaded (Talk submodel) }
                , Cmd.batch
                    [ Ports.setTitle <| TalkPage.title submodel
                    , Cmd.map TalkMsg TalkPage.onLoad
                    ]
                )

            ( TalkLoaded (Err err), _ ) ->
                toError err

            ( SearchLoaded (Ok submodel), _ ) ->
                ( { model | pageStatus = Loaded (Search submodel) }
                , Ports.setTitle <| SearchPage.title submodel
                )

            ( SearchLoaded (Err err), _ ) ->
                toError err

            ( HeaderMsg (Header.RouteTo route), _ ) ->
                ( model, Navigation.newUrl <| Route.toString route )

            ( FooterMsg Footer.RandomTalk, _ ) ->
                ( model, getRandomTalk )

            ( RandomTalkResult (Ok talk), _ ) ->
                redirectToTalkPage model talk.slug

            ( RandomTalkResult (Err err), _ ) ->
                toError err


subscriptions : Model -> Sub Msg
subscriptions model =
    case model.pageStatus of
        Loaded (Talk submodel) ->
            TalkPage.subscriptions submodel |> Sub.map TalkMsg

        _ ->
            Sub.none


view : Model -> Html Msg
view model =
    let
        content =
            case model.pageStatus of
                RedirectFrom _ ->
                    Loading.view

                Loaded Blank ->
                    text ""

                Loaded NotFound ->
                    NotFoundPage.view |> Html.map HeaderMsg

                Loaded Errored ->
                    ErrorPage.view |> Html.map HeaderMsg

                Loaded (Home submodel) ->
                    HomePage.view submodel |> Html.map HomeMsg

                Loaded (Talk submodel) ->
                    TalkPage.view submodel |> Html.map TalkMsg

                Loaded (Search submodel) ->
                    SearchPage.view submodel |> Html.map SearchMsg
    in
        div []
            [ content
            , Html.map FooterMsg Footer.view
            ]


getRandomTalk : Cmd Msg
getRandomTalk =
    let
        url =
            "/api/talks/random"
    in
        Http.send RandomTalkResult (Http.get url talkDecoder)
