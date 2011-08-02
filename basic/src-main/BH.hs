-- BH.hs
-- T. M. Kelley
-- Jun 13, 2011
-- (c) Copyright 2011 LANSLLC, all rights reserved

{-# LANGUAGE BangPatterns #-}

import Control.Parallel.Strategies
import System.Console.GetOpt
import System.Environment
import Numerical
import TryNSave
import MC
import Physical 
import Sphere1D
import Mesh
import Data.List as L
import Source
import PRNG
import Sigma_HBFC
import System.FilePath.Posix (isValid)
import Control.Parallel.MPI.Simple
import Data.Serialize (encode, decode, get, put, Serialize)
import qualified Data.Vector.Unboxed as V
import qualified Data.Vector.V3 as V3
import Control.Applicative

instance Serialize V3.Vector3 where
  put (V3.Vector3 a b c) = put [a,b,c]
  get = (\[a,b,c] -> V3.Vector3 a b c) <$> get
instance Serialize EventCount where
  put (EventCount a b c d e f g h) = put [a,b,c,d,e,f,g,h]
  get = (\[a,b,c,d,e,f,g,h] -> EventCount a b c d e f g h) <$> get
instance Serialize CellTally where
  put (CellTally m e) = put m >> put e
  get = CellTally <$> get <*> get
instance Serialize Momentum where
  put (Momentum v) = put v
  get = Momentum <$> get
instance Serialize Energy where
  put (Energy e) = put e
  get = Energy <$> get
instance Serialize EnergyWeight where
  put (EnergyWeight e) = put e
  get = EnergyWeight <$> get

instance Serialize Tally where
  put (Tally ge dep es) = put (ge, (V.toList dep), es)
  get = (\(ge, dep, es) -> Tally ge (V.fromList dep) es) <$> get

runSim :: CLOpts -> IO Tally
runSim (CLOpts { nps = n
               , inputF = infile
               , outputF = outfile
               , llimit = ll
               , ulimit = ul
               , chunkSz = chunkSize
               , simTime = dt
               , alpha   = a
               }
       ) = do
  (clls, lnuer, lnuebarr, lnuxr) <- readMatStateP infile
  let (msh,ndropped) = mkMesh clls ll ul
      mshsz = ncells msh
      lnue  = trim ndropped mshsz lnuer
      statsNuE  = calcSrcStats lnue dt n
      tllyNuE   = runManyParticles statsNuE chunkSize msh a 
  return tllyNuE

trim :: Int -> Int -> [a] -> [a]
trim d t l = take t $ drop d l


-- | Perform the simulation for several (at least one) particles
-- in a given mesh.
runManyParticles :: Mesh m => 
                    [SrcStat] ->
                    Int ->   -- chunkSize
                    m -> 
                    FP -> -- ^ alpha 
                    Tally
runManyParticles stats !chnkSz msh alph =
  let
    particles = genParticlesInCells msh testRNG stats alph
    tallies   = L.map (runParticle nuE msh) particles
    chunked   = chunk chnkSz tallies
    res       = L.map (L.foldl1' merge) chunked
                `using` parBuffer 10 rdeepseq
  in
    L.foldl1' merge res

-- | Splits a lists into chunks of the given size. TODO: Reuse
-- library functions, or move elsewhere.
chunk :: Int -> [a] -> [[a]]
chunk n = L.unfoldr go
  where
    go xs = case splitAt n xs of
              ([], []) -> Nothing
              r        -> Just r

main :: IO ()
main = mpi $ do
  size <- commSize commWorld
  rank <- commRank commWorld
  if size < 2 then do
      putStrLn "Need at least two processes to run this code"
  else do
      argv <- getArgs
      (inopts,nonOpts) <- getOpts argv
      putStrLn $  "opts = " ++ show inopts
      putStrLn $  "ns = " ++ show nonOpts
      opts <- checkOpts inopts
      putStrLn $ "opts checked ok: " ++ show opts
      tally <- runSim opts
      let root = 0 :: Rank
      if rank == root then do
        results <- gatherRecv commWorld root tally
        let total = L.foldl1' merge results
        writeTally ((outputF opts) ++ "_nuE") total
      else do
        gatherSend commWorld root tally

-- Command line processing 

data CLOpts = CLOpts {
    nps     :: Int
  , inputF  :: FilePath
  , outputF :: FilePath
  , llimit  :: FP
  , ulimit  :: FP
  , chunkSz :: Int
  , simTime :: Time
  , alpha   :: FP
  } deriving (Show,Eq)

defaultOpts :: CLOpts
defaultOpts = CLOpts 0 "" "tally" 0 1e12 (-1) (Time 1e-7) 2.0

options :: [OptDescr (CLOpts -> CLOpts)]
options = 
  [Option ['n']  ["number-particles"] 
            (ReqArg (\f opts -> opts { nps = read f}) "i")
            "number of particles to run, each species (required)"
  ,Option ['i']  ["input"] 
            (ReqArg (\f opts -> opts {inputF = f}) "FILE")
            "input FILE (required)"
  ,Option ['o']  ["output"] 
            (ReqArg (\f opts -> opts {outputF = f}) "FILE") 
            "output FILE (default \"tally\")"
  ,Option ['l']  ["lower-limit"] 
            (ReqArg (\f opts -> opts { llimit = read f}) "ll") 
            "lower limit in cm"
  ,Option ['u']  ["upper-limit"] 
            (ReqArg (\f opts -> opts { ulimit = read f}) "ul") 
            "upper limit in cm"
  ,Option ['s']  ["chunk-size"] 
            (ReqArg (\f opts -> opts { chunkSz = read f}) "sz") 
            "chunk size (defaults to nps)"
  ,Option ['d']  ["dt"] 
            (ReqArg (\f opts -> opts { simTime = Time (read f)}) "t") 
            "sim time in sec"
  ,Option ['a']  ["alpha"] 
            (ReqArg (\f opts -> opts { alpha =  (read f)}) "a") 
            "alpha"
          ]


getOpts :: [String] -> IO (CLOpts,[String])
getOpts argv = 
  case getOpt Permute options argv of
    (o,n,[]) -> return (foldl (flip id) defaultOpts o, n)
    (_,_,es) -> ioError (userError (concat es ++ usageInfo header options))
 
header :: String
header = "Usage: BH [OPTION...] N_Particles Input_File"

checkOpts :: CLOpts -> IO CLOpts
checkOpts os = case checkOptsArgsM os of 
                 Just opts -> return opts
                 Nothing -> error ("invalid arguments: " ++ show os
                                   ++ "\nexpected:\n" ++ usageInfo header options)

-- To do: instead of checking CL options in Maybe, use a
-- Writer monad that accumulates particular objections. 
checkOptsArgsM :: CLOpts -> Maybe CLOpts
checkOptsArgsM opts = 
  checkNPs opts >>= checkInput >>= checkOutput >>= checkLimits 
             >>= checkChunk >>= checkTime >>= checkAlpha

checkNPs, checkInput, checkOutput, checkLimits :: CLOpts -> Maybe CLOpts
checkChunk, checkTime, checkAlpha :: CLOpts -> Maybe CLOpts
checkNPs os@(CLOpts {nps = n}) = if n > 0 then Just os else Nothing

-- To do: for files, need better check--this forces us into IO. 
-- | Input file is valid if it exists and user can access it
checkInput os@(CLOpts {inputF = f}) = if isValid f then Just os else Nothing

-- | output file is valid if directory exists and user can write & execute it
checkOutput os@(CLOpts {outputF = f}) = if isValid f then Just os else Nothing

checkLimits os@(CLOpts {llimit = ll, ulimit = ul}) = 
  if ll < ul && ll >= 0.0
  then Just os
  else Nothing

checkTime os@(CLOpts {simTime = Time dt}) = if dt > 0.0 then Just os else Nothing

checkAlpha os@(CLOpts {alpha = a}) = if a > 0.0 then Just os else Nothing

checkChunk os@(CLOpts {nps = n, chunkSz = sz}) = 
  if sz > 0 then Just os else Just os{chunkSz = n}

-- version
-- $Id$

-- End of file
