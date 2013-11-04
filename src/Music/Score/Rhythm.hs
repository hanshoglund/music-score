
{-# LANGUAGE
    TypeFamilies,
    DeriveFunctor,
    DeriveFoldable,
    GeneralizedNewtypeDeriving,
    ScopedTypeVariables #-}

-------------------------------------------------------------------------------------
-- |
-- Copyright   : (c) Hans Hoglund 2012
--
-- License     : BSD-style
--
-- Maintainer  : hans@hanshoglund.se
-- Stability   : experimental
-- Portability : non-portable (TF,GNTD)
--
-------------------------------------------------------------------------------------

module Music.Score.Rhythm (
        -- * Rhythm type
        Rhythm(..),

        -- * Quantization
        quantize,
        dotMod,
  ) where

import Prelude hiding (foldr, concat, foldl, mapM, concatMap, maximum, sum, minimum)

import Data.Semigroup
import Control.Applicative
import Control.Monad (ap, join, MonadPlus(..))
import Data.Maybe
import Data.Either
import Data.Foldable
import Data.Traversable
import Data.Function (on)
import Data.Ord (comparing)
import Data.Ratio
import Data.VectorSpace

import Text.Parsec hiding ((<|>))
import Text.Parsec.Pos

import Music.Time
import Music.Score.Ties


data Rhythm a
    = Beat       Duration a                    -- d is divisible by 2
    | Group      [Rhythm a]                    -- normal note sequence
    | Dotted     Int (Rhythm a)                -- n > 0.
    | Tuplet     Duration (Rhythm a)           -- d is an emelent of 'tupletMods'.
    deriving (Eq, Show, Functor, Foldable)
    -- RInvTuplet  Duration (Rhythm a)

getBeatValue :: Rhythm a -> a
getBeatValue (Beat d a) = a
getBeatValue _          = error "getBeatValue: Not a beat"

getBeatDuration :: Rhythm a -> Duration
getBeatDuration (Beat d a) = d
getBeatDuration _          = error "getBeatValue: Not a beat"


instance Semigroup (Rhythm a) where
    (<>) = mappend

-- Catenates using 'Group'
instance Monoid (Rhythm a) where
    mempty = Group []
    Group as `mappend` Group bs   =  Group (as <> bs)
    r        `mappend` Group bs   =  Group ([r] <> bs)
    Group as `mappend` r          =  Group (as <> [r])

instance AdditiveGroup (Rhythm a) where
    zeroV   = error "No zeroV for (Rhythm a)"
    (^+^)   = error "No ^+^ for (Rhythm a)"
    negateV = error "No negateV for (Rhythm a)"

instance VectorSpace (Rhythm a) where
    type Scalar (Rhythm a) = Duration
    a *^ Beat d x = Beat (a*d) x

Beat d x `subDur` d' = Beat (d-d') x

{-
instance HasDuration (Rhythm a) where
    duration (Beat d _)        = d
    duration (Dotted n a)      = duration a * dotMod n
    duration (Tuplet c a)      = duration a * c
    duration (Group as)        = sum (fmap duration as)
-}

quantize :: Tiable a => [(Duration, a)] -> Either String (Rhythm a)
quantize = quantize' (atEnd rhythm)


-- Internal...

testQuantize :: [Duration] -> Either String (Rhythm ())
testQuantize = quantize' (atEnd rhythm) . fmap (\x->(x,()))

dotMod :: Int -> Duration
dotMod n = dotMods !! (n-1)

-- [3/2, 7/4, 15/8, 31/16 ..]
dotMods :: [Duration]
dotMods = zipWith (/) (fmap pred $ drop 2 times2) (drop 1 times2)
    where
        times2 = iterate (*2) 1

tupletMods :: [Duration]
tupletMods = [2/3, 4/5, {-4/6,-} 4/7, 8/9]


-- 3/2 for dots
-- 2/3, 4/5, 4/6, 4/7, 8/9, 8/10, 8/11  for ordinary tuplets
-- 3/2,      6/4                        for inverted tuplets

data RState = RState {
        timeMod :: Duration, -- time modification; notatedDur * timeMod = actualDur
        timeSub :: Duration, -- time subtraction (in bound note)
        tupleDepth :: Int
    }

instance Monoid RState where
    mempty = RState { timeMod = 1, timeSub = 0, tupleDepth = 0 }
    a `mappend` _ = a

modifyTimeMod :: (Duration -> Duration) -> RState -> RState
modifyTimeMod f (RState tm ts td) = RState (f tm) ts td

modifyTimeSub :: (Duration -> Duration) -> RState -> RState
modifyTimeSub f (RState tm ts td) = RState tm (f ts) td

modifyTupleDepth :: (Int -> Int) -> RState -> RState
modifyTupleDepth f (RState tm ts td) = RState tm ts (f td)

-- |
-- A @RhytmParser a b@ converts (Voice a) to b.
type RhythmParser a b = Parsec [(Duration, a)] RState b

quantize' :: Tiable a => RhythmParser a b -> [(Duration, a)] -> Either String b
quantize' p = left show . runParser p mempty ""

-- Matches a (duration, value) pair iff the predicate matches, returns beat
match :: Tiable a => (Duration -> a -> Bool) -> RhythmParser a (Rhythm a)
match p = tokenPrim show next test
    where
        show x        = ""
        next pos _ _  = updatePosChar pos 'x'
        test (d,x)    = if p d x then Just (Beat d x) else Nothing

-- Matches any rhythm
rhythm :: Tiable a => RhythmParser a (Rhythm a)
rhythm = Group <$> many1 (rhythm' <|> bound)

rhythmNoBound :: Tiable a => RhythmParser a (Rhythm a)
rhythmNoBound = Group <$> many1 rhythm'

rhythm' :: Tiable a => RhythmParser a (Rhythm a)
rhythm' = mzero
    <|> beat
    <|> dotted
    <|> tuplet

-- Matches a beat divisible by 2 (notated)
beat :: Tiable a => RhythmParser a (Rhythm a)
beat = do
    RState tm ts _ <- getState
    (\d -> (d^/tm) `subDur` ts) <$> match (\d _ ->
        d - ts > 0  &&  isDivisibleBy 2 (d / tm - ts))

-- | Matches a dotted rhythm
dotted :: Tiable a => RhythmParser a (Rhythm a)
dotted = msum . fmap dotted' $ [1..2]               -- max 2 dots

-- | Matches a bound rhythm
bound :: Tiable a => RhythmParser a (Rhythm a)
bound = bound' (1/2)

-- | Matches a tuplet
tuplet :: Tiable a => RhythmParser a (Rhythm a)
tuplet = msum . fmap tuplet' $ tupletMods

dotted' :: Tiable a => Int -> RhythmParser a (Rhythm a)
dotted' n = do
    modifyState $ modifyTimeMod (* dotMod n)
    a <- beat
    modifyState $ modifyTimeMod (/ dotMod n)
    return (Dotted n a)

bound' :: Tiable a => Duration -> RhythmParser a (Rhythm a)
bound' d = do
    modifyState $ modifyTimeSub (+ d)
    a <- beat
    modifyState $ modifyTimeSub (subtract d)
    let (b,c) = toTied $ getBeatValue a
    return $ Group [Beat (getBeatDuration a) b, Beat (1/2) c]
    -- FIXME doesn't know order

-- tuplet' 2/3 for triplet, 4/5 for quintuplet etc
tuplet' :: Tiable a => Duration -> RhythmParser a (Rhythm a)
tuplet' d = do
    RState _ _ depth <- getState
    onlyIf (depth < 1) $ do                         -- max 1 nested tuplets
        modifyState $ modifyTimeMod (* d)
                    . modifyTupleDepth succ
        a <- rhythmNoBound
        modifyState $ modifyTimeMod (/ d)
                    . modifyTupleDepth pred
        return (Tuplet d a)


-------------------------------------------------------------------------------------

-- | Similar to 'many1', but tries longer sequences before trying one.
-- many1long :: Stream s m t => ParsecT s u m a -> ParsecT s u m [a]
-- many1long p = try (many2 p) <|> fmap return p

-- | Similar to 'many1', but applies the parser 2 or more times.
-- many2 :: Stream s m t => ParsecT s u m a -> ParsecT s u m [a]
-- many2 p = do { x <- p; xs <- many1 p; return (x : xs) }

-- |
-- Succeed only if the entire input is consumed.
--
atEnd :: RhythmParser a b -> RhythmParser a b
atEnd p = do
    x <- p
    notFollowedBy' anyToken' <?> "end of input"
    return x
    where
        notFollowedBy' p = try $ (try p >> unexpected "") <|> return ()
        anyToken'        = tokenPrim (const "") (\pos _ _ -> pos) Just

onlyIf :: MonadPlus m => Bool -> m b -> m b
onlyIf b p = if b then p else mzero

logBaseR :: forall a . (RealFloat a, Floating a) => Rational -> Rational -> a
logBaseR k n
    | isInfinite (fromRational n :: a)      = logBaseR k (n/k) + 1
logBaseR k n
    | isDenormalized (fromRational n :: a)  = logBaseR k (n*k) - 1
logBaseR k n                         = logBase (fromRational k) (fromRational n)

-- As it sounds
isDivisibleBy :: Duration -> Duration -> Bool
isDivisibleBy n = (== 0.0) . snd . properFraction . logBaseR (toRational n) . toRational


left f (Left x)  = Left (f x)
left f (Right y) = Right y
