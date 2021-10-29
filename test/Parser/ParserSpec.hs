module Parser.ParserSpec ( spec ) where

import Test.Hspec
import Data.Either (isLeft)
import Data.Text (Text)
import qualified Data.Text as T

import Parser.Parser
import Parser.Types
import Syntax.Types
import Syntax.ATerms
import Pretty.Pretty (ppPrint, ppPrintString)
import Pretty.Types ()
import Pretty.ATerms ()

instance Show (Typ pol) where
  show typ = ppPrintString typ

typeParseExample :: Text -> Typ pol -> Spec
typeParseExample input ty = do
  it ("Parsing of " ++ T.unpack input ++ " yields " ++ ppPrintString ty) $ do
    let polRep = getPolarity ty
    let Right ty2 = runInteractiveParser (typP polRep) input
    ppPrint ty `shouldBe` ppPrint ty2

typeParseCounterEx :: Text -> PolarityRep pol -> Spec
typeParseCounterEx input polRep = do
  it ("Input " ++ T.unpack input ++ " cannot be parsed") $ do
    let res = runInteractiveParser (typP polRep) input
    res `shouldSatisfy` isLeft

atermParseExample :: Text -> ATerm Compiled -> Spec
atermParseExample input tm = do
  it ("Parsing of " ++ T.unpack input ++ " yields " ++ ppPrintString tm) $ do
    let Right (parsedTerm,_) = runInteractiveParser atermP input
    (undefined parsedTerm) `shouldBe` tm

spec :: Spec
spec = do
  describe "Check type parsing" $ do
    typeParseExample "{{ < > <<: Nat }}" $ TyRefined PosRep (MkTypeName "Nat") (TyData PosRep [])
    typeParseExample "{ 'A() }" $ TyCodata PosRep [MkXtorSig (MkXtorName Structural "A") $ MkTypArgs [] []]
    typeParseExample "{ 'A[{ 'B }] }" $ TyCodata PosRep [MkXtorSig (MkXtorName Structural "A") $ MkTypArgs [] 
      [TyCodata PosRep [MkXtorSig (MkXtorName Structural "B") $ MkTypArgs [] []] ]]
    typeParseExample "{{ {} <<: Fun}}" $ TyRefined PosRep (MkTypeName "Fun") (TyCodata PosRep [])
    typeParseExample "< 'X({{ < > <<: Nat }}) >" $ TyData PosRep [MkXtorSig (MkXtorName Structural "X") $ MkTypArgs
      [ TyRefined PosRep (MkTypeName "Nat") (TyData PosRep []) ] []]
    typeParseExample "{{ < 'A > <<: Nat }}"$ TyRefined PosRep (MkTypeName "Nat")
      (TyData PosRep [MkXtorSig (MkXtorName Structural "A") $ MkTypArgs [] []])
    typeParseExample "{{ { 'A[{ 'B }] } <<: Foo }}" $ TyRefined PosRep (MkTypeName "Foo")
      (TyCodata PosRep [MkXtorSig (MkXtorName Structural "A") $ MkTypArgs [] 
      [TyCodata PosRep [MkXtorSig (MkXtorName Structural "B") $ MkTypArgs [] []] ]])
    typeParseExample "< 'A | 'B > /\\ < 'B >"
        $ TySet NegRep [ TyData   NegRep [MkXtorSig (MkXtorName Structural "A") mempty, MkXtorSig (MkXtorName Structural "B") mempty]
                       , TyData   NegRep [MkXtorSig (MkXtorName Structural "B") mempty]]
    typeParseExample "< 'A | 'B > \\/ < 'B >"
        $ TySet PosRep [ TyData   PosRep [MkXtorSig (MkXtorName Structural "A") mempty, MkXtorSig (MkXtorName Structural "B") mempty]
                       , TyData   PosRep [MkXtorSig (MkXtorName Structural "B") mempty]]
    typeParseExample "{ 'A , 'B } /\\ { 'B }"
        $ TySet NegRep [ TyCodata NegRep [MkXtorSig (MkXtorName Structural "A") mempty, MkXtorSig (MkXtorName Structural "B") mempty]
                       , TyCodata NegRep [MkXtorSig (MkXtorName Structural "B") mempty]]
    typeParseExample "{ 'A , 'B} \\/ { 'B }"
        $ TySet PosRep [ TyCodata PosRep [MkXtorSig (MkXtorName Structural "A") mempty, MkXtorSig (MkXtorName Structural "B") mempty]
                       , TyCodata PosRep [MkXtorSig (MkXtorName Structural "B") mempty]]
    --
    typeParseCounterEx "{{ 'Ap() }" PosRep
  describe "Check aterm parsing" $ do
    atermParseExample "x y z" (Dtor () (MkXtorName Structural "Ap")
                                       (Dtor () (MkXtorName Structural "Ap") (FVar () "x") [FVar () "y"]) [FVar () "z"])
    atermParseExample "x.A.B" (Dtor () (MkXtorName Nominal "B")
                                       (Dtor () (MkXtorName Nominal "A") (FVar () "x") []) [])
    atermParseExample "f C(x)" (Dtor () (MkXtorName Structural "Ap") (FVar () "f") [Ctor () (MkXtorName Nominal "C") [FVar () "x"]])
 