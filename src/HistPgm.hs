{-# LANGUAGE FlexibleContexts #-}
module HistPgm where

import Var
import Util.PrettyPrint (PrettyPrint(..))
import Values (MaximalPrefix (..), Lit (..), Prefix (LitPEmp))
import Control.Monad.Except ( ExceptT, MonadError (throwError) )
import qualified Data.Map as M
import Types
import Control.Monad.Reader (MonadReader, asks)
import Data.Semigroup (Max)
import Control.Monad (when)

data MonOp = Neg | Not
    deriving (Eq,Ord,Show)

instance PrettyPrint MonOp where
    pp Neg = "-"
    pp Not = "!!"


data BinOp = Add | Sub | Mul | Div | Or | And | Lt | Gt | Leq | Geq | Eq | Mod
    deriving (Eq,Ord,Show)

instance PrettyPrint BinOp where
    pp Add = "+"
    pp Sub = "-"
    pp Mul = "*"
    pp Div = "/"
    pp Or = "||"
    pp And = "&&"
    pp Lt = "<"
    pp Gt = ">"
    pp Leq = "<="
    pp Geq = ">="
    pp Eq = "=="
    pp Mod = "%"

data Term =
      TmLit Lit
    | TmEps
    | TmVar Var
    | TmPair Term Term
    | TmInl Term
    | TmInr Term
    | TmNil
    | TmCons Term Term
    | TmMonOp MonOp Term
    | TmBinOp BinOp Term Term
    | TmIte Term Term Term
    deriving (Eq,Ord,Show)


instance PrettyPrint Term where
    pp = go False
        where
            go _ (TmLit l) = pp l
            go _ (TmVar x) = pp x
            go _ TmNil = "nil"
            go _ TmEps = "eps"
            go _ (TmPair e1 e2) = concat ["(",go False e1,";",go False e2,")"]
            go True e = concat ["(", go False e, ")"]
            go False (TmInl e) = "inl " ++ go True e
            go False (TmInr e) = "inl " ++ go True e
            go False (TmCons e1 e2) = concat [go True e1," :: ", go True e2]
            go False (TmMonOp m e) = pp m ++ go True e
            go False (TmBinOp b e1 e2) = concat [go True e1," ",pp b," ",go True e2]
            go False (TmIte e e1 e2) = concat ["if ", go True e," then ", go True e1, " else ",go True e2]

data SemErr =
      NonClosed Var
    | BadCons MaximalPrefix Term Term
    | NotLit Term MaximalPrefix
    | NotBool Term Lit
    | MonOpError MonOp Lit
    | BinOpError BinOp Lit Lit
    | DivideByZero

    deriving (Eq, Ord, Show)

instance PrettyPrint SemErr where
    pp (NonClosed x) = "Term not closed, encountered variable " ++ pp x
    pp (BadCons p2 e1 e2) = concat ["Could not compute cons ", pp (TmCons e1 e2), " because ", pp e2, " evaluated to ", pp p2]
    pp (NotLit e p) = concat ["Expected term ", pp e," to evaluate to a literal, it evaluated to ", pp p]
    pp (NotBool e l) = concat ["Expected term ", pp e," to evaluate to a boolean, it evaluated to ", pp l]
    pp (MonOpError m l) = concat ["Could not compute MonOp ", pp m, " of ", pp l]
    pp (BinOpError b l l') = concat ["Could not compute BinOp ", pp b, " of ", pp l, " and ", pp l']
    pp DivideByZero = "You divided by zero, silly!"

evalLit :: (MonadError SemErr m) => Term -> m Lit
evalLit e = do
    mp <- eval e
    case mp of
        LitMP l -> return l
        _ -> throwError (NotLit e mp)

evalBool e = do
    l <- evalLit e
    case l of
        LBool b -> return b
        _ -> throwError (NotBool e l)

evalMonOp :: (MonadError SemErr m) => MonOp -> Lit -> m Lit
evalMonOp Neg (LInt n) = return (LInt (-n))
evalMonOp m@Neg l = throwError (MonOpError m l)
evalMonOp Not (LBool b) = return (LBool (not b))
evalMonOp m@Not l = throwError (MonOpError m l)

evalBinOp :: (MonadError SemErr m) => BinOp -> Lit -> Lit -> m Lit
evalBinOp Add (LInt x) (LInt y) = return (LInt (x + y))
evalBinOp b@Add l l' = throwError (BinOpError b l l')
evalBinOp Sub (LInt x) (LInt y) = return (LInt (x + y))
evalBinOp b@Sub l l' = throwError (BinOpError b l l')
evalBinOp Mul (LInt x) (LInt y) = return (LInt (x * y))
evalBinOp b@Mul l l' = throwError (BinOpError b l l')
evalBinOp Div (LInt x) (LInt 0) = throwError DivideByZero
evalBinOp Div (LInt x) (LInt y) = return (LInt (x `div` y))
evalBinOp b@Div l l' = throwError (BinOpError b l l')
evalBinOp And (LBool x) (LBool y) = return (LBool (x && y))
evalBinOp b@And l l' = throwError (BinOpError b l l')
evalBinOp Or (LBool x) (LBool y) = return (LBool (x || y))
evalBinOp b@Or l l' = throwError (BinOpError b l l')
evalBinOp Lt (LInt x) (LInt y) = return (LBool (x < y))
evalBinOp b@Lt l l' = throwError (BinOpError b l l')
evalBinOp Gt (LInt x) (LInt y) = return (LBool (x > y))
evalBinOp b@Gt l l' = throwError (BinOpError b l l')
evalBinOp Geq (LInt x) (LInt y) = return (LBool (x >= y))
evalBinOp b@Geq l l' = throwError (BinOpError b l l')
evalBinOp Leq (LInt x) (LInt y) = return (LBool (x <= y))
evalBinOp b@Leq l l' = throwError (BinOpError b l l')
evalBinOp Eq (LInt x) (LInt y) = return (LBool (x == y))
evalBinOp b@Eq l l' = throwError (BinOpError b l l')
evalBinOp Mod (LInt x) (LInt y) = return (LInt (x `mod` y))
evalBinOp b@Mod l l' = throwError (BinOpError b l l')

eval :: (MonadError SemErr m) => Term -> m MaximalPrefix
eval (TmLit l) = return (LitMP l)
eval TmEps = return EpsMP
eval (TmVar x) = throwError (NonClosed x)
eval (TmMonOp m e) = do
    l <- evalLit e
    LitMP <$> evalMonOp m l
eval (TmBinOp b e1 e2) = do
    l <- evalLit e1
    l' <- evalLit e2
    LitMP <$> evalBinOp b l l'
eval (TmPair e1 e2) = do
    p1 <- eval e1
    p2 <- eval e2
    return (CatMP p1 p2)
eval (TmInl e) = SumMPA <$> eval e
eval (TmInr e) = SumMPB <$> eval e
eval TmNil = return (StMP [])
eval (TmCons e1 e2) = do
    p1 <- eval e1
    p2 <- eval e2
    case p2 of
        StMP ps -> return (StMP (p1:ps))
        _ -> throwError (BadCons p2 e1 e2)
eval (TmIte e e1 e2) = do
    b <- evalBool e
    if b then eval e1 else eval e2


type HistCtx = M.Map Var Ty

data TckErr =
     UnboundVar Var
    | WrongType Term Ty
    | WrongTypeVar Var Ty Ty
    | CheckTerm Term
    | TurnAroundErr Term Ty Ty
    | UnequalBranches Ty Ty Term
    deriving (Eq, Ord, Show)

instance PrettyPrint TckErr where
    pp (UnboundVar x) = "Unbound variable " ++ pp x ++ ". May not be in historical context."
    pp (WrongType e t) = concat ["Term ", pp e, " does not have type ", pp t]
    pp (WrongTypeVar x t t') = concat ["Expected type ", pp x, " to have type ", pp t," but it has type ", pp t']
    pp (CheckTerm e) = concat ["Term ", pp e, " cannot be inferred"]
    pp (TurnAroundErr e t t') = concat ["Expected term ", pp e," to have type ", pp t," but got type ", pp t']
    pp (UnequalBranches s s' e) = concat ["Branches of term ", pp e, " had types ", pp s," and ", pp s']

lookupVar :: (MonadReader (M.Map Var b) m, MonadError TckErr m) => Var -> m b
lookupVar x = asks (M.lookup x) >>= maybe (throwError (UnboundVar x)) return

inferMonOp :: (MonadError TckErr m, MonadReader HistCtx m) => MonOp -> Term -> m Ty
inferMonOp Neg e = check e TyInt >> return TyInt
inferMonOp Not e = check e TyBool >> return TyBool

checkMonOp :: (MonadError TckErr m, MonadReader HistCtx m) => MonOp -> Term -> Ty -> m ()
checkMonOp Neg e TyInt = check e TyInt
checkMonOp m@Neg e t = throwError (WrongType (TmMonOp m e) t)
checkMonOp Not e TyBool = check e TyBool
checkMonOp m@Not e t = throwError (WrongType (TmMonOp m e) t)

inferBinOp :: (MonadError TckErr m, MonadReader HistCtx m) => BinOp -> Term -> Term -> m Ty
inferBinOp Add e1 e2 = check e1 TyInt >> check e2 TyInt >> return TyInt
inferBinOp Sub e1 e2 = check e1 TyInt >> check e2 TyInt >> return TyInt
inferBinOp Mul e1 e2 = check e1 TyInt >> check e2 TyInt >> return TyInt
inferBinOp Div e1 e2 = check e1 TyInt >> check e2 TyInt >> return TyInt
inferBinOp Or e1 e2 = check e1 TyBool >> check e2 TyBool >> return TyBool
inferBinOp And e1 e2 = check e1 TyBool >> check e2 TyBool >> return TyBool
inferBinOp Lt e1 e2 = check e1 TyInt >> check e2 TyInt >> return TyBool
inferBinOp Gt e1 e2 = check e1 TyInt >> check e2 TyInt >> return TyBool
inferBinOp Leq e1 e2 = check e1 TyInt >> check e2 TyInt >> return TyBool
inferBinOp Geq e1 e2 = check e1 TyInt >> check e2 TyInt >> return TyBool
inferBinOp Eq e1 e2 = do
    s <- infer e1
    check e2 s
    return TyBool
inferBinOp Mod e1 e2 = check e1 TyInt >> check e2 TyInt >> return TyInt

checkBinOp :: (MonadError TckErr m, MonadReader HistCtx m) => BinOp -> Term -> Term -> Ty -> m ()
checkBinOp Add e1 e2 TyInt = check e1 TyInt >> check e2 TyInt >> return ()
checkBinOp b@Add e1 e2 t = throwError (WrongType (TmBinOp b e1 e2) t)
checkBinOp Sub e1 e2 TyInt = check e1 TyInt >> check e2 TyInt >> return ()
checkBinOp b@Sub e1 e2 t = throwError (WrongType (TmBinOp b e1 e2) t)
checkBinOp Mul e1 e2 TyInt = check e1 TyInt >> check e2 TyInt >> return ()
checkBinOp b@Mul e1 e2 t = throwError (WrongType (TmBinOp b e1 e2) t)
checkBinOp Div e1 e2 TyInt = check e1 TyInt >> check e2 TyInt >> return ()
checkBinOp b@Div e1 e2 t = throwError (WrongType (TmBinOp b e1 e2) t)
checkBinOp And e1 e2 TyBool = check e1 TyBool >> check e2 TyBool >> return ()
checkBinOp b@And e1 e2 t = throwError (WrongType (TmBinOp b e1 e2) t)
checkBinOp Or e1 e2 TyBool = check e1 TyBool >> check e2 TyBool >> return ()
checkBinOp b@Or e1 e2 t = throwError (WrongType (TmBinOp b e1 e2) t)
checkBinOp Lt e1 e2 TyBool = check e1 TyInt >> check e2 TyInt >> return ()
checkBinOp b@Lt e1 e2 t = throwError (WrongType (TmBinOp b e1 e2) t)
checkBinOp Gt e1 e2 TyBool = check e1 TyInt >> check e2 TyInt >> return ()
checkBinOp b@Gt e1 e2 t = throwError (WrongType (TmBinOp b e1 e2) t)
checkBinOp Leq e1 e2 TyBool = check e1 TyInt >> check e2 TyInt >> return ()
checkBinOp b@Leq e1 e2 t = throwError (WrongType (TmBinOp b e1 e2) t)
checkBinOp Geq e1 e2 TyBool = check e1 TyInt >> check e2 TyInt >> return ()
checkBinOp b@Geq e1 e2 t = throwError (WrongType (TmBinOp b e1 e2) t)
checkBinOp Eq e1 e2 TyBool = do
    s <- infer e1
    check e2 s
    return ()
checkBinOp b@Eq e1 e2 t = throwError (WrongType (TmBinOp b e1 e2) t)
checkBinOp Mod e1 e2 TyInt = check e1 TyInt >> check e2 TyInt >> return ()
checkBinOp b@Mod e1 e2 t = throwError (WrongType (TmBinOp b e1 e2) t)




infer :: (MonadError TckErr m, MonadReader HistCtx m) => Term -> m Ty
infer (TmLit (LInt _)) = return TyInt
infer (TmLit (LBool _)) = return TyBool
infer TmEps = return TyEps
infer (TmVar x) = lookupVar x
infer (TmMonOp m e) = inferMonOp m e
infer (TmBinOp b e1 e2) = inferBinOp b e1 e2
infer (TmPair e1 e2) = error "Cannot infer type of pair -- could be cat or par."
infer e@(TmInl _) = throwError (CheckTerm e)
infer e@(TmInr _) = throwError (CheckTerm e)
infer e@TmNil = throwError (CheckTerm e)
infer (TmCons e1 e2) = do
    s <- infer e1
    () <- check e2 (TyStar s)
    return (TyStar s)
infer e0@(TmIte e e1 e2) = do
    check e TyBool
    s <- infer e1
    s' <- infer e2
    when (s /= s') (throwError (UnequalBranches s s' e0))
    return s

turnaround :: (MonadError TckErr m, MonadReader HistCtx m) => Term -> Ty -> m ()
turnaround e t = do
    t' <- infer e
    when (t /= t') $ throwError (TurnAroundErr e t t')


check :: (MonadError TckErr m, MonadReader HistCtx m) => Term -> Ty -> m ()
check (TmLit (LInt _)) TyInt = return ()
check e@(TmLit (LInt _)) t = throwError (WrongType e t)

check (TmLit (LBool _)) TyBool = return ()
check e@(TmLit (LBool _)) t = throwError (WrongType e t)

check TmEps TyEps = return ()
check e@TmEps t = throwError (WrongType e t)

check (TmVar x) t = do
    t' <- lookupVar x
    if t == t' then return () else throwError (WrongTypeVar x t t')

check e@(TmPair e1 e2) (TyCat s t) = do
    () <- check e1 s
    () <- check e2 t
    return ()
check e@(TmPair {}) t = throwError (WrongType e t)

check (TmInl e) (TyPlus s _) = check e s
check e@(TmInl _) t = throwError (WrongType e t)

check (TmInr e) (TyPlus _ t) = check e t
check e@(TmInr _) t = throwError (WrongType e t)

check TmNil (TyStar _) = return ()
check e@TmNil t = throwError (WrongType e t)

check (TmCons e1 e2) (TyStar s) = do
    () <- check e1 s
    () <- check e2 (TyStar s)
    return ()
check e@(TmCons {}) t = throwError (WrongType e t)

check (TmMonOp m e) t = checkMonOp m e t
check (TmBinOp b e e') t = checkBinOp b e e' t

check (TmIte e e1 e2) s = do
    check e TyBool
    check e1 s
    check e2 s

substVar :: Term -> Var -> Var -> Term
substVar e@(TmLit _) _ _ = e
substVar e@TmEps _ _ = e
substVar (TmVar z) x y | z == y = TmVar x
substVar (TmVar z) _ _ = TmVar z
substVar (TmMonOp m e) x y = TmMonOp m (substVar e x y)
substVar (TmBinOp b e e') x y = TmBinOp b (substVar e x y) (substVar e' x y)
substVar (TmPair e1 e2) x y = TmPair (substVar e1 x y) (substVar e2 x y)
substVar (TmInl e) x y = TmInl (substVar e x y)
substVar (TmInr e) x y = TmInr (substVar e x y)
substVar e@TmNil _ _ = e
substVar (TmCons e1 e2) x y = TmCons (substVar e1 x y) (substVar e2 x y)
substVar (TmIte e e1 e2) x y = TmIte (substVar e x y) (substVar e1 x y) (substVar e2 x y)


maximalPrefixToTerm :: MaximalPrefix -> Term
maximalPrefixToTerm EpsMP = TmEps
maximalPrefixToTerm (LitMP l) = TmLit l
maximalPrefixToTerm (CatMP p1 p2) = TmPair (maximalPrefixToTerm p1) (maximalPrefixToTerm p2)
maximalPrefixToTerm (ParMP p1 p2) = TmPair (maximalPrefixToTerm p1) (maximalPrefixToTerm p2)
maximalPrefixToTerm (SumMPA p) = TmInl (maximalPrefixToTerm p)
maximalPrefixToTerm (SumMPB p) = TmInr (maximalPrefixToTerm p)
maximalPrefixToTerm (StMP ps) = go ps
  where
    go [] = TmNil
    go (p:ps') = TmCons (maximalPrefixToTerm p) (go ps')

maximalPrefixSubst :: (Monad m) => MaximalPrefix -> Var -> Term -> ExceptT (Var,MaximalPrefix,Term) m Term
maximalPrefixSubst _ _ e@(TmLit _) = return e
maximalPrefixSubst _ _ e@TmEps = return e
maximalPrefixSubst p x (TmVar y) | x == y = return (maximalPrefixToTerm p)
maximalPrefixSubst _ _ e@(TmVar _) = return e

maximalPrefixSubst p x (TmMonOp m e) = TmMonOp m <$> maximalPrefixSubst p x e

maximalPrefixSubst p x (TmBinOp b e1 e2) = do
  e1' <- maximalPrefixSubst p x e1
  e2' <- maximalPrefixSubst p x e2
  return (TmBinOp b e1' e2')

maximalPrefixSubst p x (TmPair e1 e2) = do
  e1' <- maximalPrefixSubst p x e1
  e2' <- maximalPrefixSubst p x e2
  return (TmPair e1' e2')
maximalPrefixSubst p x (TmInl e') = TmInl <$> maximalPrefixSubst p x e'
maximalPrefixSubst p x (TmInr e') = TmInr <$> maximalPrefixSubst p x e'


maximalPrefixSubst _ _ e@TmNil = return e
maximalPrefixSubst p x (TmCons e1 e2) = do
  e1' <- maximalPrefixSubst p x e1
  e2' <- maximalPrefixSubst p x e2
  return (TmCons e1' e2')

maximalPrefixSubst p x (TmIte e e1 e2) = do
  e' <- maximalPrefixSubst p x e
  e1' <- maximalPrefixSubst p x e1
  e2' <- maximalPrefixSubst p x e2
  return (TmIte e' e1' e2')