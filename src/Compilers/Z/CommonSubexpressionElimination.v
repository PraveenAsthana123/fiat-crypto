(** * Common Subexpression Elimination for PHOAS Syntax *)
Require Import Coq.ZArith.ZArith.
Require Import Coq.Sorting.Mergesort.
Require Import Coq.Structures.Orders.
Require Import Crypto.Compilers.Syntax.
Require Import Crypto.Compilers.Z.Syntax.
Require Import Crypto.Compilers.Z.Syntax.Util.
Require Import Crypto.Compilers.CommonSubexpressionElimination.
Require Import Crypto.Compilers.CommonSubexpressionEliminationProperties.

Local Set Decidable Equality Schemes.
Local Set Boolean Equality Schemes.
Inductive symbolic_op :=
| SOpConst (z : Z)
| SAdd
| SSub
| SMul
| SShl
| SShr
| SLand
| SLor
| SOpp
.

Definition symbolic_op_leb (x y : symbolic_op) : bool
  := match x, y with
     | SOpConst z1, SOpConst z2 => Z.leb z1 z2
     | SOpConst _, _ => true
     | _, SOpConst _ => false
     | SAdd, _ => true
     | _, SAdd => false
     | SSub, _ => true
     | _, SSub => false
     | SMul, _ => true
     | _, SMul => false
     | SShl, _ => true
     | _, SShl => false
     | SShr, _ => true
     | _, SShr => false
     | SLand, _ => true
     | _, SLand => false
     | SLor, _ => true
     | _, SLor => false
     | SOpp, _ => true
     end.

Local Notation symbolic_expr := (@symbolic_expr base_type symbolic_op).
Local Notation symbolic_expr_beq := (@symbolic_expr_beq base_type symbolic_op base_type_beq symbolic_op_beq).
Local Notation symbolic_expr_leb := (@symbolic_expr_leb base_type symbolic_op base_type_beq symbolic_op_beq symbolic_op_leb base_type_leb).

Definition symbolize_op s d (opc : op s d) : symbolic_op
  := match opc with
     | OpConst T z => SOpConst z
     | Add T1 T2 Tout => SAdd
     | Sub T1 T2 Tout => SSub
     | Mul T1 T2 Tout => SMul
     | Shl T1 T2 Tout => SShl
     | Shr T1 T2 Tout => SShr
     | Land T1 T2 Tout => SLand
     | Lor T1 T2 Tout => SLor
     | Opp T Tout => SOpp
     end.

Lemma symbolic_op_leb_total
  : forall a1 a2, symbolic_op_leb a1 a2 = true \/ symbolic_op_leb a2 a1 = true.
Proof.
  induction a1, a2; simpl; auto.
  rewrite !Z.leb_le; omega.
Qed.

Module SymbolicExprOrder <: TotalLeBool.
  Definition t := (flat_type base_type * symbolic_expr)%type.
  Definition leb (x y : t) : bool := symbolic_expr_leb (snd x) (snd y).
  Theorem leb_total : forall a1 a2, leb a1 a2 = true \/ leb a2 a1 = true.
  Proof.
    intros; apply symbolic_expr_leb_total;
      auto using internal_base_type_dec_bl, internal_symbolic_op_dec_bl, base_type_leb_total, symbolic_op_leb_total.
  Qed.
End SymbolicExprOrder.

Module Import SymbolicExprSort := Sort SymbolicExprOrder.

Fixpoint symbolic_op_args_to_list (t : flat_type base_type)
         (opc : symbolic_op) (args : symbolic_expr)
  : list (flat_type base_type * symbolic_expr)
  := match args, t with
     | SOp argT opc' args', _
       => if symbolic_op_beq opc opc'
          then symbolic_op_args_to_list argT opc args'
          else (t, args)::nil
     | SPair x y, Prod A B
       => symbolic_op_args_to_list A opc x ++ symbolic_op_args_to_list B opc y
     | STT, _
     | SVar _, _
     | SPair _ _, _
     | SFst _ _ _, _
     | SSnd _ _ _, _
     | SInvalid, _
       => (t, args)::nil
     end%list.

Fixpoint symbolic_op_list_to_args (args : list (flat_type base_type * symbolic_expr)) : symbolic_expr
  := match args with
     | nil => SInvalid
     | (t, arg)::nil => arg
     | (t1, arg1)::(t2, arg2)::nil
       => SPair arg1 arg2
     | (t1, arg1)::(((t2, arg2)::args'') as args')
       => SPair arg1 (SOp t2 SAdd (symbolic_op_list_to_args args'))
     end%list.

Definition normalize_symbolic_expr_mod_c (opc : symbolic_op) (args : symbolic_expr) : symbolic_expr
  := match opc with
     | SAdd
     | SMul
     | SLand
     | SLor
       => let ls := symbolic_op_args_to_list Unit opc args in
          let ls := sort ls in
          symbolic_op_list_to_args ls
     | SOpConst _
     | SSub
     | SShl
     | SShr
     | SOpp
       => args
     end.

Definition csef {var t} (v : exprf _ _ t) xs
  := @csef base_type symbolic_op base_type_beq symbolic_op_beq
           internal_base_type_dec_bl op symbolize_op
           normalize_symbolic_expr_mod_c
           var t v xs.

Definition cse {var} (prefix : list _) {t} (v : expr _ _ t) xs
  := @cse base_type symbolic_op base_type_beq symbolic_op_beq
          internal_base_type_dec_bl op symbolize_op
          normalize_symbolic_expr_mod_c
          var prefix t v xs.

Definition CSE {t} (e : Expr _ _ t) (prefix : forall var, list { t : flat_type base_type & exprf _ _ t })
  : Expr _ _ t
  := @CSE base_type symbolic_op base_type_beq symbolic_op_beq
          internal_base_type_dec_bl op symbolize_op
          normalize_symbolic_expr_mod_c
          t e prefix.