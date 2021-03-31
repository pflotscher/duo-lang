module TypeInference.StaticExamplesSpec ( spec )  where

import Test.Hspec
import System.FilePath

import TestUtils
import Parser.Parser
import Pretty.Pretty
import Syntax.STerms
import Syntax.Types
import Syntax.Program
import TypeInference.InferTypes
import TypeAutomata.ToAutomaton
import TypeAutomata.Subsume (typeAutEqual)
import Control.Monad (forM_)

instance Show (TypeScheme pol) where
  show = ppPrint

typecheckExample :: Environment FreeVarName -> String -> String -> Spec
typecheckExample env termS typS = do
  it (termS ++  " typechecks as: " ++ typS) $ do
      let Right term = runInteractiveParser (stermP PrdRep) termS
      let Right inferredTypeAut = inferSTermAut PrdRep term env
      let Right specTypeScheme = runInteractiveParser typeSchemeP typS
      let Right specTypeAut = typeToAut specTypeScheme
      (inferredTypeAut `typeAutEqual` specTypeAut) `shouldBe` True

prgExamples :: [(String,String)]
prgExamples = 
    [ ( "\\(x)[k] => x >> k"
        , "forall a. { 'Ap(a)[a] }" )
    , ( "'S('Z)"
        , "< 'S(< 'Z >) >" )
    , ( "\\(b,x,y)[k] => b >> match { 'True => x >> k, 'False => y >> k }"
        , "forall a. { 'Ap(< 'True | 'False >, a, a)[a] }" )
    , ( "\\(b,x,y)[k] => b >> match { 'True => x >> k, 'False => y >> k }"
        , "forall a b. { 'Ap(<'True|'False>, a, b)[a \\/ b] }" )
    , ( "\\(f)[k] => (\\(x)[k] => f >> 'Ap(x)[mu*y. f >> 'Ap(y)[k]]) >> k"
        , "forall a b. { 'Ap({ 'Ap(a \\/ b)[b] })[{ 'Ap(a)[b] }] }" )

    -- Nominal Examples
    , ( "\\(x)[k] => x >> match { TT => FF >> k, FF => TT >> k }"
        , "{ 'Ap(Bool)[Bool] }" )
    , ( "\\(x)[k] => x >> match { TT => FF >> k, FF => Z >> k }"
        , "{ 'Ap(Bool)[(Bool \\/ Nat)] }" )
    , ( "\\(x)[k] => x >> match { TT => FF >> k, FF => Z >> k }"
        , "{ 'Ap(Bool)[(Nat \\/ Bool)] }" )

    -- addNominal
    , ( "comatch { 'Ap(n,m)[k] => fix >> 'Ap( comatch { 'Ap(alpha)[k] => comatch { 'Ap(m)[k] => m >> match { Z => n >> k, S(p) => alpha >> 'Ap(p)[mu* w. S(w) >> k] }} >> k })['Ap(m)[k]] }"
        , "forall t0. { 'Ap(t0,Nat)[(t0 \\/ Nat)] }" )

    -- mltNominal
    , ( "comatch { 'Ap(n,m)[k] => fix >> 'Ap(comatch { 'Ap(alpha)[k] => comatch { 'Ap(m)[k] => m >> match { Z => Z >> k, S(p) => alpha >> 'Ap(p)[mu* w. addNominal >> 'Ap(n,w)[k]] } } >> k })['Ap(m)[k]]}"
        , "forall t0. { 'Ap((t0 /\\ Nat),Nat)[(t0 \\/ Nat)] }" )

    -- expNominal
    , ( "comatch { 'Ap(n,m)[k] => fix >> 'Ap(comatch { 'Ap(alpha)[k] => comatch { 'Ap(m)[k] => m >> match { Z => S(Z) >> k, S(p) => alpha >> 'Ap(p)[mu* w. mltNominal >> 'Ap(n,w)[k]] } } >> k })['Ap(m)[k]] }"
        , "forall t0. { 'Ap((t0 /\\ Nat),Nat)[(t0 \\/ Nat)] }" )

    -- subSafeNominal
    , ( "comatch { 'Ap(n,m)[k] => fix >> 'Ap(comatch { 'Ap(alpha)[k] => comatch { 'Ap(n)[k] => comatch { 'Ap(m)[k] => m >> match { Z => n >> k, S(mp) => n >> match { Z => n >> k, S(np) => alpha >> 'Ap(np)['Ap(mp)[k]] }}} >> k } >> k })['Ap(n)['Ap(m)[k]]]}"
        , "forall t0. { 'Ap((t0 /\\ Nat),Nat)[(t0 \\/ Nat)] }" )

    ]

testFiles :: [FilePath]
testFiles = ["prg.ds", "prg_old.ds"]

typecheckInFile :: FilePath -> Spec
typecheckInFile fp =
  describe "Typecheck specific examples" $ do
    describe ("Context is " <> fp) $ do
        env <- runIO $ getEnvironment ("examples" </> fp)
        case env of
            Left err -> it "Could not load environment" $ expectationFailure (ppPrint err)
            Right env' -> do
                forM_ prgExamples $ uncurry $ typecheckExample env'

spec :: Spec
spec = forM_ testFiles typecheckInFile
