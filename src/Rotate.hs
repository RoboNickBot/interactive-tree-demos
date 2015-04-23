import Reactive.Banana hiding (split)
import Reactive.Banana.Frameworks

import Text.Read (readMaybe)
import System.Random
import qualified Data.Map as M
import qualified Data.Char as C
import qualified Data.List as L

import Super.Canvas
import Super.Trees

treeAreaSize = (800, 195)

minNodes = 3 :: Int

data Config = Config { canvasWidth :: Double
                     , canvasHeight :: Double
                     , defaultTreeSize :: Int
                     , maximumTreeSize :: Int
                     , useStopwatch :: Bool
                     , canvasStyle :: String
                     , treeSizeInputID :: String
                     , seedInputID :: String
                     , newGameButtonID :: String}

prep :: IO (SuperCanvas, Config)
prep = do let n = "main"
              s = "background: lightgray;"
          conf <- Config
                  <$> option n "canvas-width" 900
                  <*> option n "canvas-height" 500
                  <*> option n "default-tree-size" 16
                  <*> option n "maximum-tree-size" 99
                  <*> option n "use-stopwatch" True
                  <*> option n "canvas-style" s
                  <*> option n "tree-size-input-id" "numnodes"
                  <*> option n "seed-input-id" "seed"
                  <*> option n "new-game-button-id" "newgame"
          sc <- startCanvas n 
                            ( canvasWidth conf
                            , canvasHeight conf )
                            (canvasStyle conf)
          return (sc, conf)

main = prep >>= treestuff

data NewGame = NewGame { ngNumNodes :: Int
                       , ngSeed :: Int     }

type Env = (Config, SuperCanvas, Handler TreeR)

readNewGame :: Env -> IO (GameState -> GameState)     
readNewGame (conf,sc,h) = 
  do defSeed <- (abs . fst . random) <$> newStdGen
     let defNodes = defaultTreeSize conf
         maxNodes = maximumTreeSize conf
     nn <- safeReadInput (treeSizeInputID conf) defNodes
     seed <- safeReadInput (seedInputID conf) defSeed
     let numNodes = max minNodes (min maxNodes nn)
     changeInput (treeSizeInputID conf) (show numNodes)
     changeInput (seedInputID conf) ("")
     return (newGameState (conf,sc,h) (NewGame numNodes seed))

data GameState = GameState { gsRefTree :: ColorTree
                           , gsWorkTree :: ColorTree
                           , gsForm :: SuperForm
                           , gsMoveCount :: Int      }

genTrees :: NewGame -> (ColorTree, ColorTree)
genTrees ng = randomColorTrees (ngNumNodes ng) (ngSeed ng)

emptyState :: GameState
emptyState = GameState EmptyTree EmptyTree blank 0

newGameState :: Env -> NewGame -> GameState -> GameState
newGameState (conf,sc,h) ng _ = 
  let (ref,work) = genTrees ng
  in GameState ref work blank 0

initGame :: Env -> IO GameState
initGame (conf,sc,h) = 
  do state <- readNewGame (conf,sc,h) <*> pure emptyState
     render (conf,sc,h) state
     return state

treestuff (sc,conf) = 
  do t <- newAddHandler -- for trees to return rotations
     b <- newAddHandler -- for button clicks that restart the game
     let h = snd t
     attachButton (newGameButtonID conf) 
                  (readNewGame (conf,sc,h)) 
                  (snd b)
     iState <- initGame (conf,sc,h)
     network <- compile (mkNet (conf,sc,h)
                               iState 
                               (fst t) 
                               (fst b))
     actuate network
     putStrLn "Started?"

mkNet (conf,sc,h) iState treeRs newGames = 
  do eRotations <- fromAddHandler treeRs 
     eNewGames <- fromAddHandler newGames 
     let eTreeUps = fmap (treeUp (conf,sc,h)) eRotations
         bState = accumB iState (eNewGames `union` eTreeUps)
     stateChanges <- changes bState
     reactimate' (fmap (render (conf,sc,h)) <$> stateChanges)


treeUp :: Env -> TreeR -> GameState -> GameState
treeUp (conf,sc,h) tr gs = GameState (gsRefTree gs) 
                                     (trTree tr) 
                                     (trForm tr) 
                                     (gsMoveCount gs + 1) 

render :: Env -> GameState -> IO ()
render (conf,sc,h) gs = 
  (sequence_ . fmap (animate sc 5 42)) (format (conf,sc,h) gs)

format :: Env -> GameState -> [SuperForm]
format (conf,sc,h) gs =
  let (fitRef, fitWork, fitMoves) = layouts (conf,sc,h)
      ref = gsRefTree gs
      mc = translate (100,25) 
                     (text (0,0) 
                           (200,100) 
                           ("Moves: " ++ show (gsMoveCount gs)))
  in [ combine [ fitRef (prepSTree ref)
               , fitWork (gsForm gs)
               , fitMoves mc ]
     , combine [ fitRef (prepSTree ref)
               , fitWork (prepTree h (gsWorkTree gs))
               , fitMoves mc ] ]

layouts (conf,sc,h) = 
  let padding = 30 :: Double
      toTup x = (x,x)
      treeAreaX = canvasWidth conf * 2 / 3 - padding * 2
      treeAreaY = canvasHeight conf / 2 - padding * 2
      treeBox = (treeAreaX, treeAreaY)
      
      infoX = canvasWidth conf * 1 / 3 - padding * 2
      infoY = canvasHeight conf / 3 - padding * 2
      infoBox = (infoX, infoY)

      fitRef = fit (toTup padding) treeBox
      fitWork = fit (padding, padding * 2 + treeAreaY) treeBox
      fitMoves = fit (padding * 2 + treeAreaX, padding) infoBox
  in (fitRef, fitWork, fitMoves)

randomColorTrees :: Int -> Int -> (ColorTree, ColorTree)
randomColorTrees i r = 
  let g1 = mkStdGen r
      (g2,g3) = split g1
      nodes = take i (zip (repeat True) 
                          (randomRs (Red,Yellow) g1))
      tree = randomTree nodes 
  in (tree g2, tree g3)

