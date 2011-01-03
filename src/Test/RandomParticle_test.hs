-- Testing libraries
import Test.Framework (defaultMain, testGroup)
import Test.Framework.Providers.HUnit
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.HUnit
import Test.QuickCheck

-- The library under test
import RandomParticle

-- Its dependencies
import Space
import RandomValues
import System.Random.Mersenne.Pure64
import Data.Vector.V3


-- Some initial values
origin :: Position
origin = Position (Vector3 0 0 0)

rand :: PureMT
rand = pureMT $ fromIntegral (0::Integer)

particle :: RandomParticle
particle = sampleIsoParticle rand origin (Distance 10.0)

sampleStream = (stream (Opacity 1.0) $ sampleIsoParticle rand origin (Distance 10.0))

test_sampleStream = length sampleStream @?= 7

instance Arbitrary Direction where
  arbitrary = do
    a <- arbitrary
    b <- arbitrary
    return $ randomDirection_compute a b

instance Arbitrary Position where
  arbitrary = do
    x <- arbitrary
    y <- arbitrary
    z <- arbitrary
    return $ Position (Vector3 x y z)

instance Arbitrary Distance where
  arbitrary = do
    d <- arbitrary
    return $ Distance d*10

instance Arbitrary RandomParticle where
  arbitrary = do
    seed      <- arbitrary
    position  <- arbitrary
    direction <- arbitrary
    distance  <- arbitrary
    return $ createParticle position direction distance seed

instance Arbitrary Opacity where
  arbitrary = do
    p <- arbitrary
    return $ Opacity p


-- | The direction after the step should be either the same as before,
-- or differ by the scattering vector.
prop_StepMomentum :: RandomParticle -> Bool
prop_StepMomentum p = let next = step (Opacity 1.0) p in
  case next of
    Just (Event _ (Scatter     d ), p') -> within_eps 1e-8 (d +/ rpDir p) (rpDir p')
    Just (Event _ (Termination p'), _ ) -> within_eps 1e-8 (rpDir p) (rpDir p')
    Just (Event _ (Escape p'), _)       -> within_eps 1e-8 (rpDir p) (rpDir p')
    Nothing -> True

-- Testing Steps
-- TODO: Properties for steps
--   E.g. Motion = difference in position.
--        Momentum deposition = difference in direction.          
        
-- TODO: Quickcheck step properties
        
-- Test streaming without testing events?


tests = [ testGroup "Step Operation" [testProperty "Momentum conservation" prop_StepMomentum],
          testGroup "Streaming Results" [testCase "Sample stream length" test_sampleStream]
        ]

main :: IO ()
main = defaultMain tests
