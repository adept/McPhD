{-# OPTIONS_GHC -XTypeFamilies #-}

import Particle.Simple
import Mesh.Simple
import Events.Event
import Stream

import Data.Vector.V3
import Data.List

data SimpleStream = SS { particle :: SimpleParticle, mesh :: SimpleMesh, cell :: Cell }

instance Steppable SimpleStream where
    type Particle = SimpleParticle
    step s = undefined

main = let mesh = SimpleMesh (MeshSize 10 10 10) (Vector3 0.1 0.1 0.1)
       in putStrLn $ show mesh
