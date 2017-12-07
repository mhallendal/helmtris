module Main exposing (main)

import Grid
import Block

import AnimationFrame as AF
import Char exposing (KeyCode)
import Collage
import Color exposing (..)
import Element
import Html exposing (..)
import Html.Events exposing (onClick, on, keyCode)
import Keyboard as KB
import Random
import Time
import Transform exposing (..)


playFieldSize : { cols : Int, rows : Int}
playFieldSize = { cols = 10, rows = 20 }


playFieldDimensions : { width : Int, height : Int}
playFieldDimensions =
    { width = playFieldSize.cols * Grid.cellSize
    , height = playFieldSize.rows * Grid.cellSize
    }


type alias Model =
    { playing : Bool
    , gameOver : Bool
    , landed : Grid.Grid
    , nextDrop : Time.Time
    , boost : Bool
    , score : Int
    , activeBlock : Block.Block
    , seed : Random.Seed
    }


init : (Model, Cmd Msg)
init =
    let
        (seed, block) = Block.getRandom <| Random.initialSeed 0
        grid = Grid.empty playFieldSize.cols playFieldSize.rows
    in
        ( Model False False grid 0 False 0 block seed, Cmd.none )


-- Update

type Msg
    = Tick Time.Time
    | TogglePlay
    | Left
    | Right
    | Rotate
    | Boost Bool
    | Reset
    | NoOp -- Needed by handleKey


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
    case msg of
        Tick time ->
            ( updateActiveBlock model time, Cmd.none )

        TogglePlay ->
            ( { model | playing = not model.playing }, Cmd.none )

        Left ->
            modifyActiveBlock model <| Block.moveOn -1

        Right ->
            modifyActiveBlock model <| Block.moveOn 1

        Rotate ->
            modifyActiveBlock model <| Block.rotateOn

        Boost on ->
            ( { model | boost = on }, Cmd.none)

        Reset ->
            init

        NoOp ->
            ( model, Cmd.none )


modifyActiveBlock : Model -> (Grid.Grid -> Block.Block -> Result String Block.Block) -> (Model, Cmd Msg)
modifyActiveBlock model fn =
    case fn model.landed model.activeBlock of
        Ok block ->
            ( { model | activeBlock = block }, Cmd.none )
        Err msg ->
            ( model, Cmd.none )


updateActiveBlock : Model -> Time.Time -> Model
updateActiveBlock model time =
    if time < model.nextDrop then
        model
    else
        -- Needs refactoring
        let
            block = model.activeBlock
            proposedBlock = Block.moveYOn 1 model.landed block
            interval = if model.boost then 50 else 400
            nextDrop = time + interval * Time.millisecond
        in
            case proposedBlock of
                Ok newBlock ->
                    { model | activeBlock = newBlock, nextDrop = nextDrop }
                _ ->
                    let
                        (seed, newActive) = Block.getRandom model.seed
                        landed = Block.copyOntoGrid block model.landed
                        (removed, newLanded) = Grid.removeFullRows landed
                    in
                        if Block.detectCollisionInGrid newActive newLanded then
                            gameOver model
                        else
                            { model
                            | landed = newLanded
                            , activeBlock = newActive
                            , nextDrop = nextDrop
                            , seed = seed
                            , score = model.score + removed * 10
                            }


gameOver : Model -> Model
gameOver model =
    { model | playing = False, gameOver = True}


-- Subscriptions

subscriptions : Model -> Sub Msg
subscriptions model =
    if model.playing then
        Sub.batch
            [ AF.times Tick
            , KB.downs handleDownKey
            , KB.ups handleUpKey
            ]
    else
        Sub.none

handleDownKey : KeyCode -> Msg
handleDownKey code =
    case code of
        65 ->
            Left
        68 ->
            Right
        87 ->
            Rotate
        83 ->
            Boost True
        _ ->
            NoOp

handleUpKey : KeyCode -> Msg
handleUpKey code =
    case code of
        83 ->
            Boost False
        _ ->
            NoOp


-- View

{--
  Simplify the rendering code by applying a transformation on all forms drawn.

  Since Collage in elm-graphics puts origin in the center with Y growing upwards and draws all
  forms anchored to the center as well, flip the Y axis and translate origin to be half a cellSize
  in from the top left.
--}
canvasTranslation : Transform.Transform
canvasTranslation =
    let
        startX = -(toFloat (playFieldDimensions.width - Grid.cellSize)) / 2
        startY = -(toFloat (playFieldDimensions.height - Grid.cellSize)) / 2
    in
        Transform.multiply (Transform.scaleY -1) (Transform.translation startX startY)


view : Model -> Html Msg
view model =
    let
        togglePlayStr = if model.playing then "Pause" else "Start"
        str = if model.gameOver then "GAME OVER with score: " else "Score: "
    in
        div [ ]
            [ text <| str ++ (toString model.score)
            , viewPlayField model
            , button [ onClick TogglePlay ] [ text togglePlayStr ]
            , button [ onClick Reset ] [ text "Reset" ]
            ]


viewPlayField : Model -> Html Msg
viewPlayField model =
    let
        forms = [ Grid.render 0 0 model.landed
                , Block.render model.activeBlock
                ]
    in
        Collage.collage playFieldDimensions.width playFieldDimensions.height
            [ Collage.groupTransform canvasTranslation forms ]
            |> Element.color gray
            |> Element.toHtml


-- Main

main : Program Never Model Msg
main =
    Html.program
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
    }
