
{-# LANGUAGE
    TypeFamilies,
    DeriveFunctor,
    DeriveFoldable,
    GeneralizedNewtypeDeriving #-} 

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

module Music.Time.Time (
        Time,
        fromTime,
        toTime,
        HasOnset(..),
        HasOffset(..),
        HasPreOnset(..),
        HasPostOnset(..),
        HasPostOffset(..),
        durationDefault,
        onsetDefault,
        offsetDefault,
  ) where

import Data.Semigroup
import Data.VectorSpace
import Data.AffineSpace

import Music.Time.Duration

-------------------------------------------------------------------------------------
-- Time type
-------------------------------------------------------------------------------------

-- |
-- This type represents absolute time in seconds since the start time. Note
-- that time can be negative, representing events occuring before the start time.
-- The start time is usually the the beginning of the musical performance. 
--
-- Time forms an affine space with durations as the underlying vector space,
-- that is, we can add a time to a duration to get a new time using '.+^', 
-- take the difference of two times to get a duration using '.-.'.
--
newtype Time = Time { getTime :: Rational }
    deriving (Eq, Ord, Num, Enum, Real, Fractional, RealFrac)

instance Show Time where 
    show = show . getTime

instance AdditiveGroup Time where
    zeroV = 0
    (^+^) = (+)
    negateV = negate

instance VectorSpace Time where
    type Scalar Time = Time
    (*^) = (*)

instance InnerSpace Time where 
    (<.>) = (*)

instance  AffineSpace Time where
    type Diff Time = Duration
    a .-. b =  fromTime $ a - b
    a .+^ b =  a + fromDuration b

fromTime :: Fractional a => Time -> a
fromTime = fromRational . getTime

toTime :: Real a => a -> Time
toTime = Time . toRational

-- |
-- Class of types with a position in time.
--
-- Onset and offset are logical start and stop time, i.e. the preferred beginning and end
-- of the sound, not o the the time of the attack and damp actions on an instrument,
--
-- If a type has an instance for both 'HasOnset' and 'HasDuration', the following laws
-- should hold:
-- 
-- > duration a = offset a - onset a
-- > offset a >= onset a
--
-- implying
--
-- > duration a >= 0
--
class HasOnset a where
    -- | 
    -- Get the onset of the given value.
    --
    onset  :: a -> Time

class HasOffset a where
    -- | 
    -- Get the offset of the given value.
    --
    offset :: a -> Time
                              
class HasPreOnset a where
    preOnset :: a -> Time

class HasPostOnset a where
    postOnset :: a -> Time

class HasPostOffset a where
    postOffset :: a -> Time

-- | Given 'HasOnset' and 'HasOffset' instances, this function implements 'duration'.
durationDefault :: (HasOnset a, HasOffset a) => a -> Duration
durationDefault x = offset x .-. onset x

-- | Given 'HasDuration' and 'HasOffset' instances, this function implements 'onset'.
onsetDefault :: (HasDuration a, HasOffset a) => a -> Time
onsetDefault x = offset x .-^ duration x

-- | Given 'HasOnset' and 'HasOnset' instances, this function implements 'offset'.
offsetDefault :: (HasDuration a, HasOnset a) => a -> Time
offsetDefault x = onset x .+^ duration x
