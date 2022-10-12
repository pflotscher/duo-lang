module Syntax.CST.Terms where

import Data.Text (pack)
import Loc (HasLoc (..), Loc, defaultLoc)
import Syntax.CST.Names (FreeVarName (MkFreeVarName), PrimName, XtorName (MkXtorName))

--------------------------------------------------------------------------------------------
-- Substitutions
--------------------------------------------------------------------------------------------

data TermOrStar where
  ToSTerm :: Term -> TermOrStar
  ToSStar :: TermOrStar

deriving instance Show TermOrStar

deriving instance Eq TermOrStar

newtype Substitution = MkSubstitution {unSubstitution :: [Term]}

deriving instance Show Substitution

deriving instance Eq Substitution

newtype SubstitutionI = MkSubstitutionI {unSubstitutionI :: [TermOrStar]}

deriving instance Show SubstitutionI

deriving instance Eq SubstitutionI

--------------------------------------------------------------------------------------------
-- Patterns
--------------------------------------------------------------------------------------------

data Pattern where
  PatXtor :: Loc -> XtorName -> [Pattern] -> Pattern
  PatVar :: Loc -> FreeVarName -> Pattern
  PatStar :: Loc -> Pattern
  PatWildcard :: Loc -> Pattern

--------------------------------------------


-- (1) Leaf x 
-- (2) Branch (Leaf y) t2 
-- (3) x
-- (4) *
-- (5) _
-- (6) Branch (Leaf y) (Leaf z)
-- (7) Branch t1 t2 
-- (8) t
-- -> Overlap expected between:
--    (1) and (3)
--    (1) and (4)
--    (1) and (5)
--    (1) and (8)
--    (2) and (3)
--    (2) and (4)
--    (2) and (5)
--    (2) and (6) due to Subpattern matches of (Leaf y) and (Leaf y), t2 and (Leaf z)
--    (2) and (7) due to Subpattern matches of (Leaf y) and t1, t2 and t2
--    (2) and (8)
--    (3) and (4)
--    (3) and (5)
--    (3) and (6)
--    (3) and (7)
--    (3) and (8)
--    (4) and (5)
--    (4) and (6)
--    (4) and (7)
--    (4) and (8)
--    (6) and (7) due to Subpattern matches of (Leaf y) and t1, (Leaf z) and t2
--    (6) and (8)
--    (7) and (8)
test1 :: [Pattern]
test1 =
  [ PatXtor defaultLoc (MkXtorName (pack "Leaf")) [PatVar defaultLoc (MkFreeVarName (pack "x"))],
    PatXtor
      defaultLoc
      (MkXtorName (pack "Branch"))
      [ PatXtor defaultLoc (MkXtorName (pack "Leaf")) [PatVar defaultLoc (MkFreeVarName (pack "y"))],
        PatVar defaultLoc (MkFreeVarName (pack "t2"))
      ],
    PatVar defaultLoc (MkFreeVarName (pack "x")),
    PatStar defaultLoc,
    PatWildcard defaultLoc,
    PatXtor
      defaultLoc
      (MkXtorName (pack "Branch"))
      [ PatXtor defaultLoc (MkXtorName (pack "Leaf")) [PatVar defaultLoc (MkFreeVarName (pack "y"))],
        PatXtor defaultLoc (MkXtorName (pack "Leaf")) [PatVar defaultLoc (MkFreeVarName (pack "z"))]
      ],
    PatXtor
      defaultLoc
      (MkXtorName (pack "Branch"))
      [ PatVar defaultLoc (MkFreeVarName (pack "t1")),
        PatVar defaultLoc (MkFreeVarName (pack "t2"))
      ],
    PatVar defaultLoc (MkFreeVarName (pack "t"))
  ]

-- (1) m
-- (2) *
-- (3) Nothing 
-- (4) Maybe x 
-- (5) _
-- -> Overlap expected between:
--    (1) and (2)
--    (1) and (3)
--    (1) and (4)
--    (1) and (5)
--    (2) and (3)
--    (2) and (4)
--    (2) and (5)
--    (3) and (5)
--    (4) and (5)
test2 :: [Pattern]
test2 =
  [ PatVar defaultLoc (MkFreeVarName (pack "m")),
    PatStar defaultLoc,
    PatXtor defaultLoc (MkXtorName (pack "Nothing")) [],
    PatXtor defaultLoc (MkXtorName (pack "Maybe")) [PatVar defaultLoc (MkFreeVarName (pack "x"))],
    PatWildcard defaultLoc
  ]

-- No Overlap expected.
test3 :: [Pattern]
test3 = []

-- No Overlap expected.
test4 :: [Pattern]
test4 = [PatStar defaultLoc]

-- (1) Node y Empty (Node z Empty Empty)
-- (2) Node z Empty Empty
-- No Overlap expected.
test5 :: [Pattern]
test5 =
  [ PatXtor
      defaultLoc
      (MkXtorName (pack "Node"))
      [ PatVar defaultLoc (MkFreeVarName (pack "y")),
        PatXtor defaultLoc (MkXtorName (pack "Empty")) [],
        PatXtor defaultLoc (MkXtorName (pack "Node")) [ PatVar defaultLoc (MkFreeVarName (pack "z")),
                                                        PatXtor defaultLoc (MkXtorName (pack "Empty")) [],
                                                        PatXtor defaultLoc (MkXtorName (pack "Empty")) []]],
    PatXtor
      defaultLoc
      (MkXtorName (pack "Node"))
      [ PatVar defaultLoc (MkFreeVarName (pack "z")),
        PatXtor defaultLoc (MkXtorName (pack "Empty")) [],
        PatXtor defaultLoc (MkXtorName (pack "Empty")) []]]

-- (1) x
-- (2) z
-- (3) x
-- -> Overlap expected between:
--    (1) and (2)
--    (1) and (3)
--    (2) and (3)
test6 :: [Pattern]
test6 =
  [ PatVar defaultLoc (MkFreeVarName (pack "x")),
    PatVar defaultLoc (MkFreeVarName (pack "z")),
    PatVar defaultLoc (MkFreeVarName (pack "x"))
  ]

-- (1) Cons x (Cons y (Cons z zs))
-- (2) Cons x (Cons y (Cons z (Cons m ms)))
-- -> Overlap expected between:
--    (1) and (2) (due to Subpattern Overlap between x and x, (Cons y (Cons z zs)) and (Cons y (Cons z (Cons m ms))))
test7 :: [Pattern]
test7 = [PatXtor defaultLoc (MkXtorName (pack "Cons")) 
          [ PatVar defaultLoc (MkFreeVarName (pack "x")),
            PatXtor defaultLoc (MkXtorName (pack "Cons")) 
              [ PatVar defaultLoc (MkFreeVarName (pack "y")),
                PatXtor defaultLoc (MkXtorName (pack "Cons")) [PatVar defaultLoc (MkFreeVarName (pack "z")), PatVar defaultLoc (MkFreeVarName (pack "zs"))]]],
         PatXtor defaultLoc (MkXtorName (pack "Cons")) 
          [PatVar defaultLoc (MkFreeVarName (pack "x")),
          PatXtor defaultLoc (MkXtorName (pack "Cons")) 
            [PatVar defaultLoc (MkFreeVarName (pack "y")),
            PatXtor defaultLoc (MkXtorName (pack "Cons")) 
              [PatVar defaultLoc (MkFreeVarName (pack "z")),
               PatXtor defaultLoc (MkXtorName (pack "Cons")) [PatVar defaultLoc (MkFreeVarName (pack "m")), PatVar defaultLoc (MkFreeVarName (pack "ms"))]]]]]

-- (1) Branch (Leaf x) (Leaf y)
-- (2) Branch (Leaf x) (Branch (Leaf y1) (Leaf y2))
-- No Overlap expected.
test8 :: [Pattern]
test8 = [PatXtor
          defaultLoc
          (MkXtorName (pack "Branch"))
          [ PatXtor defaultLoc (MkXtorName (pack "Leaf")) [PatVar defaultLoc (MkFreeVarName (pack "x"))],
            PatXtor defaultLoc (MkXtorName (pack "Leaf")) [PatVar defaultLoc (MkFreeVarName (pack "y"))]
          ],
         PatXtor
          defaultLoc
          (MkXtorName (pack "Branch"))
          [ PatXtor defaultLoc (MkXtorName (pack "Leaf")) [PatVar defaultLoc (MkFreeVarName (pack "x"))],
            PatXtor
            defaultLoc
            (MkXtorName (pack "Branch"))
            [ PatXtor defaultLoc (MkXtorName (pack "Leaf")) [PatVar defaultLoc (MkFreeVarName (pack "y1"))],
              PatXtor defaultLoc (MkXtorName (pack "Leaf")) [PatVar defaultLoc (MkFreeVarName (pack "y2"))]
            ]
          ]]

-- | An Overlap Message is a String
type OverlapMsg = String

-- | An Overlap may be an Overlap Message.
type Overlap = Maybe OverlapMsg

-- | Helper for readable display of Overlap objects.
printOverlap :: Overlap -> String
printOverlap (Just msg) = msg 
printOverlap Nothing    = "No Overlap found."

-- | Generates the Overlap of Patterns between one another.
-- For testing purposes, best display via putStrLn $ printOverlap $ overlap test<X>...
overlap :: [Pattern] -> Overlap
overlap []        = Nothing
overlap (x : xs)  =
  let xOverlaps = map (overlapA2 x) xs
  in  concatOverlaps $ xOverlaps ++ [overlap xs]
  where
    -- | Reduces multiple potential Overlap Messages into one potential Overlap Message.
    concatOverlaps :: [Overlap] -> Overlap
    concatOverlaps xs =
      let concatRule = \x y -> x ++ "\n\n" ++ y
      in  foldr (liftm2 concatRule) Nothing xs
      where
        liftm2 :: (a -> a -> a) -> Maybe a -> Maybe a -> Maybe a
        liftm2 _ x          Nothing   = x
        liftm2 _ Nothing    y         = y
        liftm2 f (Just x)   (Just y)  = Just $ (f x y)

    -- | Generates an Overlap Message for patterns p1 p2.
    overlapMsg :: Pattern -> Pattern -> OverlapMsg
    overlapMsg p1 p2 =
      let p1Str = patternToStr p1
          p2Str = patternToStr p2
      in  "Overlap found:\n" ++ p1Str ++ " overlaps with " ++ p2Str ++ "\n"

    -- | Readable Conversion of Pattern to String.
    patternToStr :: Pattern -> String
    patternToStr (PatVar loc varName)     = "Variable Pattern " ++ (show varName) ++ "in: " ++ (show loc)
    patternToStr (PatStar loc)            = "* Pattern in: " ++ (show loc)
    patternToStr (PatWildcard loc)        = "Wildcard Pattern in: " ++ (show loc)
    patternToStr (PatXtor loc xtorName _) = "Constructor Pattern " ++ (show xtorName) ++ "in: " ++ (show loc)

    -- | Determines for 2x Patterns p1 p2 a potential Overlap message on p1 'containing' p2 or p2 'containing' p1.
    overlapA2 :: Pattern -> Pattern -> Overlap
    -- An Overlap may occur for two De/Constructors if their Names match.
    overlapA2 p1@(PatXtor _ xXtorName xPatterns) 
              p2@(PatXtor _ yXtorName yPatterns) =
                if    xXtorName /= yXtorName
                then  Nothing
                else  let subPatternsOverlaps = zipWith overlapA2 xPatterns yPatterns
                          --Only if all Pairs of Subpatterns truly overlap is an Overlap found.
                          subPatternsOverlap =  if   (elem Nothing subPatternsOverlaps) 
                                                then Nothing 
                                                else concatOverlaps subPatternsOverlaps
                      in  case subPatternsOverlap of
                            Nothing                       -> Nothing
                            (Just subPatternsOverlapMsg)  ->
                              Just $
                                (overlapMsg p1 p2)
                                ++ "due to the all Subpatterns overlapping as follows:\n"
                                ++ "--------------------------------->\n"
                                ++ subPatternsOverlapMsg
                                ++ "---------------------------------<\n"
                                    
    -- If either p1 or p2 is no De/Constructor, they already overlap.
    overlapA2 p1 p2 = Just $ overlapMsg p1 p2

--------------------------------------------

deriving instance Show Pattern

deriving instance Eq Pattern

instance HasLoc Pattern where
  getLoc (PatXtor loc _ _) = loc
  getLoc (PatVar loc _) = loc
  getLoc (PatStar loc) = loc
  getLoc (PatWildcard loc) = loc

--------------------------------------------------------------------------------------------
-- Cases/Cocases
--------------------------------------------------------------------------------------------

data TermCase = MkTermCase
  { tmcase_loc :: Loc,
    tmcase_pat :: Pattern,
    tmcase_term :: Term
  }

deriving instance Show TermCase

deriving instance Eq TermCase

instance HasLoc TermCase where
  getLoc tc = tmcase_loc tc

--------------------------------------------------------------------------------------------
-- Terms
--------------------------------------------------------------------------------------------

data NominalStructural where
  Nominal :: NominalStructural
  Structural :: NominalStructural
  Refinement :: NominalStructural
  deriving (Eq, Ord, Show)

data Term where
  PrimTerm :: Loc -> PrimName -> Substitution -> Term
  Var :: Loc -> FreeVarName -> Term
  Xtor :: Loc -> XtorName -> SubstitutionI -> Term
  Semi :: Loc -> XtorName -> SubstitutionI -> Term -> Term
  Case :: Loc -> [TermCase] -> Term
  CaseOf :: Loc -> Term -> [TermCase] -> Term
  Cocase :: Loc -> [TermCase] -> Term
  CocaseOf :: Loc -> Term -> [TermCase] -> Term
  MuAbs :: Loc -> FreeVarName -> Term -> Term
  Dtor :: Loc -> XtorName -> Term -> SubstitutionI -> Term
  PrimLitI64 :: Loc -> Integer -> Term
  PrimLitF64 :: Loc -> Double -> Term
  PrimLitChar :: Loc -> Char -> Term
  PrimLitString :: Loc -> String -> Term
  NatLit :: Loc -> NominalStructural -> Int -> Term
  TermParens :: Loc -> Term -> Term
  FunApp :: Loc -> Term -> Term -> Term
  Lambda :: Loc -> FreeVarName -> Term -> Term
  CoLambda :: Loc -> FreeVarName -> Term -> Term
  Apply :: Loc -> Term -> Term -> Term

deriving instance Show Term

deriving instance Eq Term

instance HasLoc Term where
  getLoc (Var loc _) = loc
  getLoc (Xtor loc _ _) = loc
  getLoc (Semi loc _ _ _) = loc
  getLoc (MuAbs loc _ _) = loc
  getLoc (Dtor loc _ _ _) = loc
  getLoc (Case loc _) = loc
  getLoc (CaseOf loc _ _) = loc
  getLoc (Cocase loc _) = loc
  getLoc (CocaseOf loc _ _) = loc
  getLoc (PrimLitI64 loc _) = loc
  getLoc (PrimLitF64 loc _) = loc
  getLoc (PrimLitChar loc _) = loc
  getLoc (PrimLitString loc _) = loc
  getLoc (NatLit loc _ _) = loc
  getLoc (TermParens loc _) = loc
  getLoc (FunApp loc _ _) = loc
  getLoc (Lambda loc _ _) = loc
  getLoc (CoLambda loc _ _) = loc
  getLoc (Apply loc _ _) = loc
  getLoc (PrimTerm loc _ _) = loc
