module UI.Tracks.Scene.List exposing (Dependencies, DerivedColors, containerId, defaultItemView, deriveColors, scrollToNowPlaying, scrollToTop, view)

import Browser.Dom as Dom
import Chunky exposing (..)
import Color exposing (Color)
import Color.Manipulate as Color
import Conditional exposing (ifThenElse)
import Coordinates
import Css.Classes as C
import Html exposing (Html, text)
import Html.Attributes exposing (id, style, tabindex)
import Html.Events
import Html.Events.Extra.Mouse as Mouse
import Html.Lazy
import InfiniteList
import Json.Decode as Decode
import List.Ext as List
import Material.Icons as Icons
import Material.Icons.Types exposing (Coloring(..))
import Maybe.Extra as Maybe
import Queue
import Task
import Tracks exposing (..)
import UI.DnD as DnD
import UI.Kit
import UI.Queue.Types as Queue
import UI.Tracks.Scene as Scene
import UI.Tracks.Types exposing (Msg(..))
import UI.Types as UI exposing (Msg(..))



-- 🗺


type alias Dependencies =
    { bgColor : Maybe Color
    , darkMode : Bool
    , height : Float
    , isTouchDevice : Bool
    , isVisible : Bool
    , showAlbum : Bool
    }


type alias DerivedColors =
    { background : String
    , subtle : String
    , text : String
    }


view : Dependencies -> List IdentifiedTrack -> InfiniteList.Model -> Bool -> Maybe Queue.Item -> Maybe String -> SortBy -> SortDirection -> List Int -> Maybe (DnD.Model Int) -> Html Msg
view deps harvest infiniteList favouritesOnly nowPlaying searchTerm sortBy sortDirection selectedTrackIndexes maybeDnD =
    brick
        ((::)
            (tabindex (ifThenElse deps.isVisible 0 -1))
            viewAttributes
        )
        [ C.flex_basis_0
        , C.flex_grow
        , C.outline_none
        , C.overflow_x_hidden
        , C.relative
        , C.select_none
        , C.scrolling_touch
        , C.text_xs

        --
        , C.md__text_almost_sm

        --
        , case maybeDnD of
            Just dnd ->
                if deps.isTouchDevice && DnD.isDragging dnd then
                    C.overflow_y_hidden

                else
                    C.overflow_y_auto

            Nothing ->
                C.overflow_y_auto
        ]
        [ Scene.shadow

        -- Header
        ---------
        , Html.Lazy.lazy4
            header
            (Maybe.isJust maybeDnD)
            deps.showAlbum
            sortBy
            sortDirection

        -- List
        -------
        , Html.Lazy.lazy7
            infiniteListView
            deps
            harvest
            infiniteList
            favouritesOnly
            searchTerm
            ( nowPlaying, selectedTrackIndexes )
            maybeDnD
        ]


containerId : String
containerId =
    "diffuse__track-list"


scrollToNowPlaying : List IdentifiedTrack -> IdentifiedTrack -> Cmd Msg
scrollToNowPlaying harvest ( identifiers, _ ) =
    harvest
        |> List.take identifiers.indexInList
        |> List.foldl (\a -> (+) <| dynamicRowHeight 0 a) 0
        |> (\n -> 22 - toFloat rowHeight / 2 + 2 + toFloat n)
        |> Dom.setViewportOf containerId 0
        |> Task.attempt (always Bypass)


scrollToTop : Cmd Msg
scrollToTop =
    Task.attempt (always UI.Bypass) (Dom.setViewportOf containerId 0 0)


viewAttributes : List (Html.Attribute Msg)
viewAttributes =
    [ InfiniteList.onScroll (InfiniteListMsg >> TracksMsg)
    , id containerId
    , C.overscroll_none
    ]



-- HEADERS


header : Bool -> Bool -> SortBy -> SortDirection -> Html Msg
header isPlaylist showAlbum sortBy sortDirection =
    let
        sortIcon =
            (if sortDirection == Desc then
                Icons.expand_less

             else
                Icons.expand_more
            )
                15
                Inherit

        maybeSortIcon s =
            ifThenElse (sortBy == s) (Just sortIcon) Nothing
    in
    chunk
        [ C.antialiased
        , C.bg_white
        , C.border_b
        , C.border_gray_300
        , C.flex
        , C.font_semibold
        , C.relative
        , C.text_base06
        , C.text_xxs
        , C.z_20

        -- Dark mode
        ------------
        , C.dark__bg_darkest_hour
        , C.dark__border_base01
        , C.dark__text_base03
        ]
        (if isPlaylist && showAlbum then
            [ headerColumn "" 4.5 Nothing Bypass
            , headerColumn "#" 4.5 Nothing Bypass
            , headerColumn "Title" 36.0 Nothing Bypass
            , headerColumn "Artist" 27.5 Nothing Bypass
            , headerColumn "Album" 27.5 Nothing Bypass
            ]

         else if isPlaylist then
            [ headerColumn "" 4.5 Nothing Bypass
            , headerColumn "#" 4.5 Nothing Bypass
            , headerColumn "Title" 49.75 Nothing Bypass
            , headerColumn "Artist" 41.25 Nothing Bypass
            ]

         else if showAlbum then
            [ headerColumn "" 4.5 Nothing Bypass
            , headerColumn "Title" 37.5 (maybeSortIcon Title) (TracksMsg <| SortBy Title)
            , headerColumn "Artist" 29.0 (maybeSortIcon Artist) (TracksMsg <| SortBy Artist)
            , headerColumn "Album" 29.0 (maybeSortIcon Album) (TracksMsg <| SortBy Album)
            ]

         else
            [ headerColumn "" 5.75 Nothing Bypass
            , headerColumn "Title" 51.25 (maybeSortIcon Title) (TracksMsg <| SortBy Title)
            , headerColumn "Artist" 43 (maybeSortIcon Artist) (TracksMsg <| SortBy Artist)
            ]
        )



-- HEADER COLUMN


headerColumn : String -> Float -> Maybe (Html Msg) -> Msg -> Html Msg
headerColumn text_ width maybeSortIcon msg =
    brick
        [ Html.Events.onClick msg

        --
        , style "min-width" columnMinWidth
        , style "width" (String.fromFloat width ++ "%")
        ]
        [ C.border_l
        , C.border_gray_300
        , C.leading_relaxed
        , C.pl_2
        , C.pr_2
        , C.pt_px
        , C.relative

        --
        , case msg of
            Bypass ->
                C.cursor_default

            _ ->
                C.cursor_pointer

        --
        , C.first__border_l_0
        , C.first__cursor_default
        , C.first__pl_4
        , C.last__pr_4

        -- Dark mode
        ------------
        , C.dark__border_base01
        ]
        [ chunk
            [ C.mt_px, C.opacity_90, C.pt_px ]
            [ Html.text text_ ]
        , case maybeSortIcon of
            Just sortIcon ->
                chunk
                    [ C.absolute
                    , C.neg_translate_y_1over2
                    , C.mr_1
                    , C.opacity_90
                    , C.right_0
                    , C.top_1over2
                    , C.transform
                    ]
                    [ sortIcon ]

            Nothing ->
                nothing
        ]



-- INFINITE LIST


infiniteListView : Dependencies -> List IdentifiedTrack -> InfiniteList.Model -> Bool -> Maybe String -> ( Maybe Queue.Item, List Int ) -> Maybe (DnD.Model Int) -> Html Msg
infiniteListView deps harvest infiniteList favouritesOnly searchTerm ( nowPlaying, selectedTrackIndexes ) maybeDnD =
    let
        derivedColors =
            deriveColors { bgColor = deps.bgColor, darkMode = deps.darkMode }
    in
    { itemView =
        case maybeDnD of
            Just dnd ->
                playlistItemView
                    favouritesOnly
                    nowPlaying
                    searchTerm
                    selectedTrackIndexes
                    dnd
                    deps.showAlbum
                    deps.darkMode
                    derivedColors

            _ ->
                defaultItemView
                    { derivedColors = derivedColors
                    , favouritesOnly = favouritesOnly
                    , nowPlaying = nowPlaying
                    , roundedCorners = False
                    , selectedTrackIndexes = selectedTrackIndexes
                    , showAlbum = deps.showAlbum
                    , showArtist = True
                    , showGroup = True
                    }

    --
    , itemHeight = InfiniteList.withVariableHeight dynamicRowHeight
    , containerHeight = round deps.height
    }
        |> InfiniteList.config
        |> InfiniteList.withCustomContainer infiniteListContainer
        |> (\config ->
                InfiniteList.view
                    config
                    infiniteList
                    harvest
           )


infiniteListContainer :
    List ( String, String )
    -> List (Html msg)
    -> Html msg
infiniteListContainer styles =
    styles
        |> List.filterMap
            (\( k, v ) ->
                if k == "padding" then
                    Nothing

                else
                    Just (style k v)
            )
        |> List.append listStyles
        |> Html.div


deriveColors : { bgColor : Maybe Color, darkMode : Bool } -> DerivedColors
deriveColors { bgColor, darkMode } =
    let
        color =
            Maybe.withDefault UI.Kit.colors.text bgColor
    in
    if darkMode then
        { background = Color.toCssString color
        , subtle = Color.toCssString (Color.darken 0.1 color)
        , text = Color.toCssString (Color.darken 0.475 color)
        }

    else
        { background = Color.toCssString (Color.fadeOut 0.625 color)
        , subtle = Color.toCssString (Color.fadeOut 0.575 color)
        , text = Color.toCssString (Color.darken 0.3 color)
        }


listStyles : List (Html.Attribute msg)
listStyles =
    [ C.pb_2
    , C.pt_1
    ]


dynamicRowHeight : Int -> IdentifiedTrack -> Int
dynamicRowHeight _ ( i, t ) =
    if Tracks.shouldRenderGroup i then
        16 + 18 + 12 + rowHeight

    else
        rowHeight



-- INFINITE LIST ITEM


defaultItemView :
    { derivedColors : DerivedColors
    , favouritesOnly : Bool
    , nowPlaying : Maybe Queue.Item
    , roundedCorners : Bool
    , selectedTrackIndexes : List Int
    , showAlbum : Bool
    , showArtist : Bool
    , showGroup : Bool
    }
    -> Int
    -> Int
    -> IdentifiedTrack
    -> Html Msg
defaultItemView args _ idx identifiedTrack =
    let
        { derivedColors, favouritesOnly, nowPlaying, roundedCorners, selectedTrackIndexes, showAlbum, showArtist, showGroup } =
            args

        ( identifiers, track ) =
            identifiedTrack

        shouldRenderGroup =
            showGroup && Tracks.shouldRenderGroup identifiers

        isSelected =
            List.member idx selectedTrackIndexes

        isOddRow =
            modBy 2 idx == 1

        rowIdentifiers =
            { isMissing = identifiers.isMissing
            , isNowPlaying = Maybe.unwrap False (.identifiedTrack >> isNowPlaying identifiedTrack) nowPlaying
            , isSelected = isSelected
            }

        favIdentifiers =
            { indexInList = identifiers.indexInList
            , isFavourite = identifiers.isFavourite
            , isNowPlaying = rowIdentifiers.isNowPlaying
            , isSelected = isSelected
            }
    in
    Html.div
        []
        [ if shouldRenderGroup then
            Scene.group { index = idx } identifiers

          else
            nothing

        --
        , brick
            (List.concat
                [ rowStyles idx rowIdentifiers derivedColors

                --
                , List.append
                    (if isSelected then
                        [ touchContextMenuEvent identifiedTrack Nothing ]

                     else
                        []
                    )
                    [ mouseContextMenuEvent identifiedTrack
                    , playEvent identifiedTrack
                    , selectEvent idx
                    ]
                ]
            )
            [ C.flex
            , C.items_center

            --
            , ifThenElse identifiers.isMissing C.cursor_default C.cursor_pointer
            , ifThenElse isSelected C.font_semibold C.font_normal
            , ifThenElse roundedCorners C.rounded C.border_r_0

            --
            , ifThenElse
                isOddRow
                C.bg_white
                C.bg_gray_100

            -- Dark mode
            ------------
            , ifThenElse
                isOddRow
                C.dark__bg_darkest_hour
                C.dark__bg_near_darkest_hour
            ]
            (if not showArtist && not showAlbum then
                [ favouriteColumn "5.75%" favouritesOnly favIdentifiers derivedColors
                , otherColumn "94.25%" False track.tags.title
                ]

             else if not showArtist && showAlbum then
                [ favouriteColumn "5.75%" favouritesOnly favIdentifiers derivedColors
                , otherColumn "51.25%" False track.tags.title
                , otherColumn "43%" False track.tags.album
                ]

             else if showArtist && not showAlbum then
                [ favouriteColumn "5.75%" favouritesOnly favIdentifiers derivedColors
                , otherColumn "51.25%" False track.tags.title
                , otherColumn "43%" False track.tags.artist
                ]

             else
                [ favouriteColumn defFavColWidth favouritesOnly favIdentifiers derivedColors
                , otherColumn "37.5%" False track.tags.title
                , otherColumn "29.0%" False track.tags.artist
                , otherColumn "29.0%" True track.tags.album
                ]
            )
        ]


playlistItemView : Bool -> Maybe Queue.Item -> Maybe String -> List Int -> DnD.Model Int -> Bool -> Bool -> DerivedColors -> Int -> Int -> IdentifiedTrack -> Html Msg
playlistItemView favouritesOnly nowPlaying searchTerm selectedTrackIndexes dnd showAlbum darkMode derivedColors _ idx identifiedTrack =
    let
        ( identifiers, track ) =
            identifiedTrack

        listIdx =
            identifiers.indexInList

        dragEnv =
            { model = dnd
            , toMsg = DnD
            }

        isSelected =
            List.member idx selectedTrackIndexes

        isOddRow =
            modBy 2 idx == 1

        rowIdentifiers =
            { isMissing = identifiers.isMissing
            , isNowPlaying = Maybe.unwrap False (.identifiedTrack >> isNowPlaying identifiedTrack) nowPlaying
            , isSelected = isSelected
            }

        favIdentifiers =
            { indexInList = identifiers.indexInList
            , isFavourite = identifiers.isFavourite
            , isNowPlaying = rowIdentifiers.isNowPlaying
            , isSelected = isSelected
            }
    in
    brick
        (List.concat
            [ rowStyles idx rowIdentifiers derivedColors

            --
            , List.append
                (if isSelected && not favouritesOnly && Maybe.isNothing searchTerm then
                    [ touchContextMenuEvent identifiedTrack (Just dragEnv)
                    , DnD.listenToStart dragEnv listIdx
                    ]

                 else if isSelected then
                    [ touchContextMenuEvent identifiedTrack (Just dragEnv)
                    ]

                 else
                    []
                )
                [ mouseContextMenuEvent identifiedTrack
                , playEvent identifiedTrack
                , selectEvent idx
                ]

            --
            , DnD.listenToEnterLeave dragEnv listIdx

            --
            , if DnD.isBeingDraggedOver listIdx dnd then
                [ dragIndicator darkMode ]

              else
                []
            ]
        )
        [ C.flex
        , C.items_center

        --
        , ifThenElse identifiers.isMissing C.cursor_default C.cursor_pointer
        , ifThenElse isSelected C.font_semibold C.font_normal

        --
        , ifThenElse
            isOddRow
            C.bg_white
            C.bg_gray_100

        -- Dark mode
        ------------
        , ifThenElse
            isOddRow
            C.dark__bg_darkest_hour
            C.dark__bg_near_darkest_hour
        ]
        (if showAlbum then
            [ favouriteColumn defFavColWidth favouritesOnly favIdentifiers derivedColors
            , playlistIndexColumn (Maybe.withDefault 0 identifiers.indexInPlaylist)
            , otherColumn "36.0%" False track.tags.title
            , otherColumn "27.5%" False track.tags.artist
            , otherColumn "27.5%" True track.tags.album
            ]

         else
            [ favouriteColumn defFavColWidth favouritesOnly favIdentifiers derivedColors
            , playlistIndexColumn (Maybe.withDefault 0 identifiers.indexInPlaylist)
            , otherColumn "49.75%" False track.tags.title
            , otherColumn "41.25%" False track.tags.artist
            ]
        )


mouseContextMenuEvent : IdentifiedTrack -> Html.Attribute Msg
mouseContextMenuEvent ( i, _ ) =
    Html.Events.custom
        "contextmenu"
        (Decode.map
            (\event ->
                { message =
                    if event.keys.shift then
                        Bypass

                    else
                        event.clientPos
                            |> Coordinates.fromTuple
                            |> ShowTracksMenuWithSmallDelay
                                (Just i.indexInList)
                                { alt = event.keys.alt }
                            |> TracksMsg

                --
                , stopPropagation = True
                , preventDefault = True
                }
            )
            Mouse.eventDecoder
        )


touchContextMenuEvent : IdentifiedTrack -> Maybe (DnD.Environment Int Msg) -> Html.Attribute Msg
touchContextMenuEvent ( i, _ ) maybeDragEnv =
    Html.Events.custom
        "longtap"
        (Decode.map2
            (\x y ->
                { message =
                    -- Only show menu when not dragging something
                    case Maybe.andThen (.model >> DnD.modelTarget) maybeDragEnv of
                        Just _ ->
                            Bypass

                        Nothing ->
                            { x = x, y = y }
                                |> ShowTracksMenu
                                    (Just i.indexInList)
                                    { alt = False }
                                |> TracksMsg

                --
                , stopPropagation = False
                , preventDefault = False
                }
            )
            (Decode.field "x" Decode.float)
            (Decode.field "y" Decode.float)
        )


playEvent : IdentifiedTrack -> Html.Attribute Msg
playEvent ( i, t ) =
    Html.Events.custom
        "dbltap"
        (Decode.succeed
            { message =
                if i.isMissing then
                    Bypass

                else
                    ( i, t )
                        |> Queue.InjectFirstAndPlay
                        |> QueueMsg

            --
            , stopPropagation = True
            , preventDefault = True
            }
        )


selectEvent : Int -> Html.Attribute Msg
selectEvent idx =
    Html.Events.custom
        "tap"
        (Decode.map2
            (\shiftKey button ->
                { message =
                    case button of
                        0 ->
                            { shiftKey = shiftKey }
                                |> MarkAsSelected idx
                                |> TracksMsg

                        _ ->
                            Bypass

                --
                , stopPropagation = True
                , preventDefault = False
                }
            )
            (Decode.at [ "originalEvent", "shiftKey" ] Decode.bool)
            (Decode.oneOf
                [ Decode.at [ "originalEvent", "button" ] Decode.int
                , Decode.succeed 0
                ]
            )
        )



-- ROWS


rowHeight : Int
rowHeight =
    35


rowStyles : Int -> { isMissing : Bool, isNowPlaying : Bool, isSelected : Bool } -> DerivedColors -> List (Html.Attribute msg)
rowStyles idx { isMissing, isNowPlaying, isSelected } derivedColors =
    let
        bgColor =
            if isNowPlaying then
                derivedColors.background

            else
                ""

        color =
            if isNowPlaying then
                derivedColors.text

            else if isMissing then
                rowFontColors.gray

            else
                ""
    in
    [ style "background-color" bgColor
    , style "color" color
    , style "height" (String.fromInt rowHeight ++ "px")
    ]



-- COLUMNS


defFavColWidth =
    "4.5%"


columnMinWidth =
    "28px"


favouriteColumn : String -> Bool -> { isFavourite : Bool, indexInList : Int, isNowPlaying : Bool, isSelected : Bool } -> DerivedColors -> Html Msg
favouriteColumn columnWidth favouritesOnly identifiers derivedColors =
    brick
        ((++)
            [ style "width" columnWidth
            , identifiers.indexInList
                |> ToggleFavourite
                |> TracksMsg
                |> Html.Events.onClick
            ]
            (favouriteColumnStyles favouritesOnly identifiers derivedColors)
        )
        [ C.flex_shrink_0
        , C.font_normal
        , C.pl_4
        , C.text_gray_500

        -- Dark mode
        ------------
        , C.dark__text_base02
        ]
        [ if identifiers.isFavourite then
            text "t"

          else
            text "f"
        ]


favouriteColumnStyles : Bool -> { isFavourite : Bool, indexInList : Int, isNowPlaying : Bool, isSelected : Bool } -> DerivedColors -> List (Html.Attribute msg)
favouriteColumnStyles favouritesOnly { isFavourite, isNowPlaying, isSelected } derivedColors =
    let
        color =
            if isNowPlaying && isFavourite then
                derivedColors.text

            else if isNowPlaying then
                derivedColors.subtle

            else if favouritesOnly || not isFavourite then
                ""

            else
                favColors.red
    in
    [ style "color" color
    , style "font-family" "or-favourites"
    , style "min-width" columnMinWidth
    ]


playlistIndexColumn : Int -> Html msg
playlistIndexColumn indexInPlaylist =
    brick
        (otherColumnStyles "4.5%")
        [ C.pl_2
        , C.pr_2
        , C.pointer_events_none
        , C.truncate
        ]
        [ indexInPlaylist
            |> (+) 1
            |> String.fromInt
            |> text
        ]


otherColumn : String -> Bool -> String -> Html msg
otherColumn width isLast text_ =
    brick
        (otherColumnStyles width)
        [ C.pl_2
        , C.pr_2
        , C.pointer_events_none
        , C.truncate

        --
        , C.last__pr_4
        ]
        [ text text_ ]


otherColumnStyles : String -> List (Html.Attribute msg)
otherColumnStyles columnWidth =
    [ style "min-width" columnMinWidth
    , style "width" columnWidth
    ]



-- 🖼


favColors =
    { gray = Color.toCssString (Color.rgb255 220 220 220)
    , red = Color.toCssString UI.Kit.colorKit.base08
    }


rowFontColors =
    { gray = Color.toCssString UI.Kit.colorKit.base04
    , white = Color.toCssString (Color.rgb 1 1 1)
    }


dragIndicator : Bool -> Html.Attribute msg
dragIndicator darkMode =
    let
        color =
            if darkMode then
                UI.Kit.colors.gray_300

            else
                UI.Kit.colorKit.base03
    in
    style "box-shadow" ("0 1px 0 0 " ++ Color.toCssString color ++ " inset")
