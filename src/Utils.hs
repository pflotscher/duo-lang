module Utils where

import Data.Char (isSpace)
import Data.Foldable (foldl')
import Data.List.NonEmpty (NonEmpty(..))
import Data.Set (Set)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import Text.Megaparsec.Pos

----------------------------------------------------------------------------------
-- Source code locations
----------------------------------------------------------------------------------

data Loc = Loc SourcePos SourcePos
  deriving (Eq, Ord)

instance Show Loc where
  show (Loc _s1 _s2) = "<loc>"

defaultLoc :: Loc
defaultLoc = Loc (SourcePos "" (mkPos 1) (mkPos 1)) (SourcePos "" (mkPos 1) (mkPos 1))

-- | A typeclass for things which can be mapped to a source code location.
class HasLoc a where
  getLoc :: a -> Loc

----------------------------------------------------------------------------------
-- Helper Functions
----------------------------------------------------------------------------------

allEq :: Eq a => [a] -> Bool
allEq [] = True
allEq (x:xs) = all (==x) xs

intersections :: Ord a => NonEmpty (Set a) -> Set a
intersections (s :| ss) = foldl' S.intersection s ss

enumerate :: [a] -> [(Int,a)]
enumerate = zip [0..]

trimStr :: String -> String
trimStr = f . f
  where f = reverse . dropWhile isSpace

trim :: Text -> Text
trim = f . f
  where f = T.reverse . T.dropWhile isSpace


indexMaybe :: [a] -> Int -> Maybe a
indexMaybe xs i | 0 <= i && i <= length xs -1 = Just (xs !! i)
                | otherwise = Nothing

data Verbosity = Verbose | Silent
  deriving (Eq)
