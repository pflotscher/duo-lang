module ExampleSpec where

import           Test.Hspec
import           Control.Monad (forM_, when)

import qualified Data.Map as M
import Data.Either (isRight)

import TestUtils
import Parser
import Syntax.Terms
import Syntax.Program
import Syntax.TypeGraph
import Utils
import GenerateConstraints
import SolveConstraints
import TypeAutomata.Determinize
import TypeAutomata.FlowAnalysis
import TypeAutomata.Minimize (minimize)
import TypeAutomata.ToAutomaton
import TypeAutomata.Subsume (typeAutEqual)

failingExamples :: [String]
failingExamples = ["div2and3"]

checkTerm :: Environment -> (FreeVarName, Term Prd ()) -> SpecWith ()
checkTerm env (name,term) = it (name ++ " can be typechecked correctly") $ typecheck env term `shouldSatisfy` isRight

typecheck :: Environment -> Term Prd () -> Either Error TypeAutDet
typecheck env t = do
  (typedTerm, css, uvars) <- generateConstraints t env
  typeAut <- solveConstraints css uvars (typedTermToType env typedTerm) Prd
  let typeAutDet0 = determinize typeAut
  let typeAutDet = removeAdmissableFlowEdges typeAutDet0
  let minTypeAut = minimize typeAutDet
  return minTypeAut

typecheckExample :: Environment -> String -> String -> Spec
typecheckExample env termS typS = do
  it (termS ++  " typechecks as: " ++ typS) $ do
      let Right term = runEnvParser (termP PrdRep) env termS
      let Right inferredTypeAut = typecheck env term
      let Right specTypeScheme = runEnvParser typeSchemeP mempty typS
      let Right specTypeAut = typeToAut specTypeScheme
      (inferredTypeAut `typeAutEqual` specTypeAut) `shouldBe` True

spec :: Spec
spec = do
  describe "All examples typecheck" $ do
    env <- runIO $ getEnvironment "prg.txt" failingExamples
    when (failingExamples /= []) $ it "Some examples were ignored:" $ pendingWith $ unwords failingExamples
    forM_  (M.toList (prdEnv env)) $ \term -> do
      checkTerm env term
  describe "Typecheck specific examples" $ do
    env <- runIO $ getEnvironment "prg.txt" []
    typecheckExample env "\\(x)[k] => x >> k" "forall a. { 'Ap(a)[a] }"
    typecheckExample env "'S('Z)" "< 'S(< 'Z >) >"
    typecheckExample env "\\(b,x,y)[k] => b >> match { 'True => x >> k, 'False => y >> k }"
                         "forall a. { 'Ap(< 'True | 'False >, a, a)[a] }"
    typecheckExample env "\\(b,x,y)[k] => b >> match { 'True => x >> k, 'False => y >> k }"
                         "forall a b. { 'Ap(<'True|'False>, a, b)[a \\/ b] }"
    typecheckExample env "\\(f)[k] => (\\(x)[k] => f >> 'Ap(x)[mu*y. f >> 'Ap(y)[k]]) >> k"
                         "forall a b. { 'Ap({ 'Ap(a \\/ b)[b] })[{ 'Ap(a)[b] }] }"
    -- Nominal Examples
    typecheckExample env "\\(x)[k] => x >> match { TT => FF >> k, FF => TT >> k }"
                         "{ 'Ap(Bool)[Bool] }"
    typecheckExample env "\\(x)[k] => x >> match { TT => FF >> k, FF => Zero >> k }"
                         "{ 'Ap(Bool)[(Bool \\/ Nat)] }"
    typecheckExample env "\\(x)[k] => x >> match { TT => FF >> k, FF => Zero >> k }"
                         "{ 'Ap(Bool)[(Nat \\/ Bool)] }"
    -- predNominal
    typecheckExample env "comatch { 'Ap(n)[k] => n >> match { Succ(m) => m >> k } }"
                         "{ 'Ap(Nat)[Nat] }"
    -- addNominal
    typecheckExample env "comatch { 'Ap(n,m)[k] => fix >> 'Ap( comatch { 'Ap(alpha)[k] => comatch { 'Ap(m)[k] => m >> match { Zero => n >> k, Succ(p) => alpha >> 'Ap(p)[mu* w. Succ(w) >> k] }} >> k })['Ap(m)[k]] }"
                         "forall t0. { 'Ap(t0,Nat)[(t0 \\/ Nat)] }"
    -- mltNominal
    typecheckExample env "comatch { 'Ap(n,m)[k] => fix >> 'Ap(comatch { 'Ap(alpha)[k] => comatch { 'Ap(m)[k] => m >> match { Zero => Zero >> k, Succ(p) => alpha >> 'Ap(p)[mu* w. addNominal >> 'Ap(n,w)[k]] } } >> k })['Ap(m)[k]]}"
                         "forall t0. { 'Ap((t0 /\\ Nat),Nat)[(t0 \\/ Nat)] }"
    -- expNominal
    typecheckExample env "comatch { 'Ap(n,m)[k] => fix >> 'Ap(comatch { 'Ap(alpha)[k] => comatch { 'Ap(m)[k] => m >> match { Zero => Succ(Zero) >> k, Succ(p) => alpha >> 'Ap(p)[mu* w. mltNominal >> 'Ap(n,w)[k]] } } >> k })['Ap(m)[k]] }"
                         "forall t0. { 'Ap((t0 /\\ Nat),Nat)[(t0 \\/ Nat)] }"
    -- subNominal
    typecheckExample env "comatch { 'Ap(n,m)[k] => fix >> 'Ap(comatch { 'Ap(alpha)[k] => comatch { 'Ap(m)[k] => m >> match { Zero => n >> k, Succ(p) => alpha >> 'Ap(p)[mu*w. predNominal >> 'Ap(w)[k]] }} >> k })['Ap(m)[k]] }"
                         "{ 'Ap(Nat,Nat)[Nat] }"
    -- subSafeNominal
    typecheckExample env "comatch { 'Ap(n,m)[k] => fix >> 'Ap(comatch { 'Ap(alpha)[k] => comatch { 'Ap(n)[k] => comatch { 'Ap(m)[k] => m >> match { Zero => n >> k, Succ(mp) => n >> match { Zero => n >> k, Succ(np) => alpha >> 'Ap(np)['Ap(mp)[k]] }}} >> k } >> k })['Ap(n)['Ap(m)[k]]]}"
                         "forall t0. { 'Ap((t0 /\\ Nat),Nat)[(t0 \\/ Nat)] }"

