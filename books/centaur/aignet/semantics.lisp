; AIGNET - And-Inverter Graph Networks
; Copyright (C) 2013 Centaur Technology
;
; Contact:
;   Centaur Technology Formal Verification Group
;   7600-C N. Capital of Texas Highway, Suite 300, Austin, TX 78731, USA.
;   http://www.centtech.com/
;
; This program is free software; you can redistribute it and/or modify it under
; the terms of the GNU General Public License as published by the Free Software
; Foundation; either version 2 of the License, or (at your option) any later
; version.  This program is distributed in the hope that it will be useful but
; WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
; more details.  You should have received a copy of the GNU General Public
; License along with this program; if not, write to the Free Software
; Foundation, Inc., 51 Franklin Street, Suite 500, Boston, MA 02110-1335, USA.
;
; Original author: Sol Swords <sswords@centtech.com>

(in-package "AIGNET")
;; (include-book "idp")
;; (include-book "litp")
;; (include-book "cutil/defmvtypes" :dir :system)
;; (include-book "data-structures/list-defthms" :dir :system)
;; (include-book "str/natstr" :dir :system)
;; (include-book "tools/defmacfun" :dir :system)
;; (include-book "tools/stobj-frame" :dir :system)
;; (include-book "tools/clone-stobj" :dir :system)
(include-book "add-ons/hash-stobjs" :dir :system)
(include-book "arrays")
(include-book "centaur/misc/2d-arr" :dir :system)
;; (include-book "std/ks/two-nats-measure" :dir :system)
;; (include-book "centaur/misc/arith-equivs" :dir :system)
;; (include-book "centaur/misc/hons-extra" :dir :system)
(include-book "centaur/misc/iter" :dir :system)
(include-book "centaur/misc/natarr" :dir :system)
(include-book "centaur/misc/nth-equiv" :dir :system)
;; (include-book "centaur/misc/numlist" :dir :system)
;; (include-book "centaur/misc/stobj-swap" :dir :system)
;; (include-book "centaur/vl/util/cwtime" :dir :system)
;; (include-book "clause-processors/instantiate" :dir :system)
(include-book "clause-processors/stobj-preservation" :dir :system)
(include-book "clause-processors/generalize" :dir :system)
(include-book "clause-processors/find-subterms" :dir :system)

(local (include-book "arithmetic/top-with-meta" :dir :system))
(local (include-book "centaur/bitops/ihsext-basics" :dir :system))
(local (in-theory (enable* acl2::arith-equiv-forwarding)))
(local (in-theory (disable sets::double-containment)))
(local (in-theory (disable nth update-nth
                           acl2::nfix-when-not-natp
                           resize-list
                           acl2::resize-list-when-empty
                           acl2::make-list-ac-redef
                           sets::double-containment
                           sets::sets-are-true-lists
                           make-list-ac)))

(set-waterfall-parallelism nil) ; currently unknown why we need to disable
                                ; waterfall-parallelism; something to examine

(local (in-theory (disable true-listp-update-nth
                           acl2::nth-with-large-index)))

(local (defthmd equal-1-to-bitp
         (implies (and (not (equal x 0))
                       (bitp x))
                  (equal (equal x 1) t))
         :hints(("Goal" :in-theory (enable bitp)))))

;; sigh
(defmacro mksym (pkg &rest concats)
  `(intern-in-package-of-symbol
    (concatenate 'string . ,concats)
    ,pkg))

(defthmd redundant-update-nth
  (implies (and (< (nfix n) (len x))
                (equal v (nth n x)))
           (equal (update-nth n v x)
                  x))
  :hints(("Goal" :in-theory (enable nth update-nth))))

;; BOZO move somewhere else
(defrefinement nth-equiv bits-equiv :hints(("Goal" :in-theory (enable bits-equiv))))

(defmacro const-type () 0)
(defmacro gate-type () 1)
(defmacro in-type () 2)
(defmacro out-type () 3)

(defxdoc aignet
  :short "AIGNET is an and-inverter graph implementation: a representation for
both Boolean functions and finite-state machines."
  :long
  "<p>An and-inverter graph (AIG) at its most basic is a DAG whose nodes are either
AND gates, outputs, or inputs.  Outputs have 1 descendant, ANDs have 2, and
inputs have none.  An edge may point to an AND or an input, but not an output.
Each edge has a Boolean attribute signifying whether it is negated or not.</p>

<p>We call this a combinational AIG.  AIGNET, following packages like ABC,
implements a sequential AIG, by dividing the inputs and outputs into two
categories, \"register\" and \"primary\".  A sequential AIG can be seen as a
combinational AIG by just ignoring these distinctions; when we wish to ignore
the register/primary distinctions we refer to <i> combinational inputs </i>
and <i> combinational outputs </i>.  Confusingly, combinational inputs of
the register type are called <i>register outputs</i> -- it is an output
from a register, but are read (like inputs) by the combinational logic -- and
combinational outputs of the register type are called <i>register
inputs</i> -- they are inputs to registers, but are written (like outputs)
by the combinational logic.  Register inputs, like primary outputs, have one
descendant and may not be the descendant of another node; register outputs,
like primary inputs, have no descendants and may be the descendant of another
node.</p>

<p>Sequential semantics for an AIG network can be summarized as follows:<br/>
 Initially, assign initial values to the register output nodes.<br/>
 Every cycle,<br/>
  <ul><li>assign values to the primary inputs</li>
      <li>copy values from register outputs to corresponding register inputs</li>
      <li>compute values of AND gates in topological order</li>
      <li>compute values of primary outputs and register inputs.</li></ul></p>

<p>During the period of computing values for ANDs/primary outputs/register inputs,
the circuit is basically treated as combinational -- register outputs and
primary inputs are treated identically, as are primary outputs and register
inputs.</p>

<p>Usage and implementation are discussed in the subtopics.</p>")

(defsection aignet-impl
  :parents (aignet)
  :short "Implementation details of AIGNET"
  :long
  "<p>The AIGNET network consists mainly of an array of nodes representing a
topologically sorted DAG described in @(see aignet).  This uses a stobj called
@('AIGNET').</p>

<p>Each node in the graph has an ID, a natural number that can be used to look
up that node in the array.  However, often our functions take arguments that
may be a node or its negation; we encode this as a <i>literal</i>, as 2*ID+NEG,
where NEG is 1 signifying negated or 0 signifying not negated.</p>

<p>One arbitrary well-formedness condition that we impose on all AIGNET
networks is that it must have a unique constant-false node with index 0.
Therefore, the literal 0 is constant-false (the constant-false node, not
negated), and the literal 1 is constant-true (the constant-false node,
negated).</p>

<p>Information about each node is stored in the node array as two consecutive
32-bit numbers, and the node ID corresponds to its position: the two array
indices of a node are 2*ID and 2*ID+1.  The two 32-bit values contained at
these locations are broken down into two 30-bit data slots and four extra bits.
Three of the four extra bits encode the type of the node, and the last extra
bit encodes the phase of the node, which is its value when all inputs/registers
are 0.  The meaning of the 30-bit data slots depends on the type of node; in
some cases it stores a literal.</p>

<p>The encoding is broken down, least-significant bits first, as:</p>
<ul>
<li>2 bits:   combinational type</li>
<li>30 bits:  data slot 0</li>
<li>1 bit:    register flag</li>
<li>1 bit:    phase</li>
<li>30 bits:  data slot 1.</li></ul>

<p>The combinational types are:</p>
<ul>
<li>0:   constant false</li>
<li>1:   gate</li>
<li>2:   input</li>
<li>3:   output</li></ul>

<p>The register flag only applies to combinational inputs/outputs; it should be
0 for constants/gates (but should also be ignored in those cases).  An input
with the register flag set is a register output, and an output with the
register flag set is a register input.  (Remember that the output of a register
is an input to the combinational logic, and the input to a register is an
output from the combinational logic.)</p>

<p>So there are, in total, six types of object, encoded as follows:
<code>
Name               Type encoding          Register flag
Constant                 0                    -
AND gate                 1                    -
Primary input            2                    0
Register output          2                    1
Primary output           3                    0
Register input           3                    1.
</code></p>

<p>Only objects with type 0, 1, 2 -- constants, gates, and combinational inputs
-- may be fanins (descendents) of AND or combinational output objects;
combinational outputs (type 3) may not.</p>

<p>The meanings of the two 30-bit data slots vary based on the type:</p>

<p>Constant: both data 0 and 1 are meaningless, and should be set to 0 but
ignored</p>

<p>AND gates: data 0 and 1 are literals encoding the fanins to the gate.  The
ID part of each literal must be less than the gate ID.</p>

<p>Combinational inputs: data 0 is ignored and should be 0, and fanin 1 gives
the PI or register number, sequentially assigned and unique among
PI/registers.</p>

<p>Primary outputs: data 0 is the fanin (literal) of the output, whose ID must
be less than the output node ID.  Data 1 is the output number.</p>

<p>Register inputs: data 0 is the fanin (literal) of the register, whose ID
must be less than this node's ID.  Fanin 1 is the ID of the corresponding
register output, which must also be less than this node's ID.  (The register
number of the RI is the register number of the corresponding RO.)</p>

<p>Having separate register input and output objects is somewhat awkward in
terms of saying when a network is well-formed.  In some sense, it's not
well-formed unless every RO has a corresponding RI.  But the RIs can't be
added until their input cones are built, and we'd like to be able to say
the network is well-formed in some sense while it is being built.  So when
an RO has no corresponding RI, we will say it is simply not updated -- its
value under sequential evalutation remains the same at each frame.  A
separate predicate can check that this isn't the case, but we won't
generally require this for guards etc.  Furthermore, for convenience we
also allow RIs with fanin 1 set to 0 -- in this case, they are not proper
RIs because they do not connect to an RO, and they have no register
number.  They are also basically irrelevant to any sequential computation,
because no RI gets updated with their previous value.</p>

<p>We require that each RI object occur later (have a larger ID) than its
corresponding RO object.  This allows a couple of conveniences:</p>
<ul>
<li>there is a function for adding an RO and another function for adding an
  RI which connects it to an existing RO.  If we allowed RIs to occur first,
  then we'd need an additional pair of functions, for adding an unconnected
  RI and for adding an RO connected to an RI.  Maybe we could avoid this by
  separately allowing RO/RIs to be connected, but this seems knotty in terms
  of well-formednes.</li>
<li>When doing a sequential simulation or similar operation that involves
  repeated sweeps across the AIG nodes, an RO node will be reached before
  the corresponding RI's previous value is overwritten.  So we don't need an
  addtional step of copying RI-&gt;RO values between frames.</li></ul>
<p>Also, a strategy that might alleviate any inconvenience due to needing to
add the RO before the RI: at the point of adding the RI, check whether the
RO already exists and add it first if not.</p>

<p>An AIGNET network is designed to have objects added one at a time without
later modification.  That is, new objects may be added, but existing
objects are not changed.  The object array itself (along with its size)
contains enough information to fully replicate the network; in this sense,
all other information recorded is auxiliary.  But we do also keep arrays
of inputs, outputs, and registers.  The input and output arrays simply
hold the IDs of inputs/outputs in the order that they were added (as
described below, each input/output object records its input/output
numbers, i.e. the index in the input/output array that points back to
it).  The register array is a bit more complicated, because there are
typically two nodes (register input and register output) associated with
each register.  Each entry in the register array contains the ID of either
a register input or output.  If it is a register input, then the register
is incomplete, i.e. its output hasn't been added yet.  If it is a register
output, then we have a complete register: the register array points to the
register output node, which points to the register input node, which has
the index in the register array.</p>")



;; (defsection aignet-untranslate
;;   (defun untranslate-preproc-node-types (term wrld)
;;     (declare (ignore wrld))
;;     (case-match term
;;       (('equal ('node->type ('nth-node id ('nth ''6 aignet))) ('quote typenum))
;;        (case typenum
;;          (0 `(equal (id->type ,id ,aignet) (const-type)))
;;          (1 `(equal (id->type ,id ,aignet) (gate-type)))
;;          (2 `(equal (id->type ,id ,aignet) (in-type)))
;;          (3 `(equal (id->type ,id ,aignet) (out-type)))
;;          (otherwise term)))
;;       (& term)))

;;   (defmacro use-aignet-untrans ()
;;     '(local
;;       (table acl2::user-defined-functions-table 'acl2::untranslate-preprocess
;;              'untranslate-preproc-node-types))))

;; (use-aignet-untrans)

;; (in-theory (disable acl2::aignetp))



(defsection misc

  (defthm lookup-id-implies-aignet-idp
    (implies (consp (lookup-id id aignet))
             (aignet-idp id aignet))
    :hints(("Goal" :in-theory (enable aignet-idp lookup-id))))

  (defthm aignet-idp-of-node-count-of-extension
    (implies (aignet-extension-p aignet prev)
             (aignet-idp (node-count prev) aignet))
    :hints(("Goal" :in-theory (enable aignet-extension-p
                                      aignet-idp))))

  (defthm lookup-id-of-cons
    (equal (lookup-id id (cons node rest))
           (if (equal (nfix id) (+ 1 (node-count rest)))
               (cons node rest)
             (lookup-id id rest)))
    :hints(("Goal" :in-theory (enable lookup-id))))

  
  (defun equiv-search-type-alist (type-alist goaltype equiv lhs rhs unify-subst wrld)
    (declare (xargs :mode :program))
    (b*  (((when (endp type-alist))
           (mv nil nil))
          ((list* term type ?ttree) (car type-alist))
          ((unless
               (and (acl2::ts-subsetp type goaltype)
                    (consp term)
                    (symbolp (car term))
                    (member equiv
                            (fgetprop (car term) 'acl2::coarsenings
                                      nil wrld))))
           (equiv-search-type-alist (cdr type-alist) goaltype equiv lhs rhs unify-subst
                                    wrld))
          ((mv ans new-unify-subst)
           (acl2::one-way-unify1 lhs (cadr term) unify-subst))
          ((mv ans new-unify-subst)
           (if ans
               (acl2::one-way-unify1 rhs (caddr term) new-unify-subst)
             (mv nil nil)))
          ((when ans) (mv t new-unify-subst))
          ;; try (equiv rhs lhs)
          ((mv ans new-unify-subst)
           (acl2::one-way-unify1 lhs (caddr term) unify-subst))
          ((mv ans new-unify-subst)
           (if ans
               (acl2::one-way-unify1 rhs (cadr term) new-unify-subst)
             (mv nil nil)))
          ((when ans) (mv t new-unify-subst)))
      (equiv-search-type-alist (cdr type-alist) goaltype equiv lhs rhs unify-subst
                               wrld)))

  ;; Term has at least one variable not bound in unify-subst.  Search
  ;; type-alist for term matching (equiv1 lhs rhs) or (equiv1 rhs lhs)
  ;; and return the matching free variables.
  (defun match-equiv-or-refinement (equiv var binding-term mfc state)
    (declare (xargs :mode :program :stobjs state))
    (b* (; (*mfc* mfc)
         (unify-subst (acl2::mfc-unify-subst mfc))
         ((mv erp tbind)
          (acl2::translate-cmp binding-term t t nil 'match-equiv-or-refinement (w state)
                               (acl2::default-state-vars t)))
         ((when erp)
          (er hard? erp "~@0" tbind))
         (type-alist (acl2::mfc-type-alist mfc))
         ;; Does the var unify with the binding-term already?
         ((mv ok new-unify-subst)
          (acl2::one-way-unify1 tbind (cdr (assoc var unify-subst)) unify-subst))
         ((when ok)
          (butlast new-unify-subst (length unify-subst)))
         ((mv ok new-unify-subst)
          (equiv-search-type-alist type-alist acl2::*ts-non-nil* equiv var tbind unify-subst
                                   (w state)))
         ((unless ok) nil))
      (butlast new-unify-subst (length unify-subst))))


  (defun match-equiv-or-refinement-lst (equiv var terms mfc state)
    (declare (xargs :mode :program :stobjs state))
    (if (atom terms)
        nil
      (or (match-equiv-or-refinement equiv var (car terms) mfc state)
          (match-equiv-or-refinement-lst equiv var (cdr terms) mfc state))))
    

  (defthm lookup-id-of-node-count
    (equal (lookup-id (node-count x) x)
           x)
    :hints(("Goal" :in-theory (enable lookup-id))))

  (defthm lookup-id-of-node-count-bind
    (implies (and (bind-free (match-equiv-or-refinement-lst
                              'nat-equiv 'id
                              '((node-count x)
                                (+ 1 (node-count (cdr x))))
                              mfc state)
                             (x))
                  (syntaxp (not (subtermp id x)))
                  (nat-equiv id (node-count x))
                  (aignet-extension-p y x))
             (equal (lookup-id id y)
                    x))
    :hints(("Goal" :in-theory (e/d () (nat-equiv)))))

  (defthm node-count-of-lookup-id-when-consp
    (implies (consp (lookup-id id aignet))
             (equal (node-count (lookup-id id aignet))
                    id))
    :hints(("Goal" :in-theory (enable lookup-id))))

  (defthm posp-when-consp-of-lookup-id
    (implies (consp (lookup-id id aignet))
             (posp id))
    :hints(("Goal" :in-theory (enable lookup-id)))
    :rule-classes :forward-chaining)

  (defthm aignet-idp-of-0
    (aignet-idp 0 aignet)
    :hints(("Goal" :in-theory (enable aignet-idp))))

  (defthm aignet-litp-of-0-and-1
    (and (aignet-litp 0 aignet)
         (aignet-litp 1 aignet))
    :hints(("Goal" :in-theory (enable aignet-litp))))

  (defthm aignet-litp-of-mk-lit-lit-id
    (equal (aignet-litp (mk-lit (lit-id lit) neg) aignet)
           (aignet-litp lit aignet))
    :hints(("Goal" :in-theory (enable aignet-litp))))

  (defthm aignet-litp-of-mk-lit-0
    (aignet-litp (mk-lit 0 neg) aignet)
    :hints(("Goal" :in-theory (enable aignet-litp)))))
                    

(defsection ionum-uniqueness

  (in-theory (disable lookup-id-in-bounds))


  (defthm lookup-id-by-stype
    (implies (not (equal (stype (car (lookup-id id aignet)))
                         (const-stype)))
             (lookup-id id aignet)))

  (defthm stype-counts-unique
    (implies (and (equal type (stype (car (lookup-id id1 aignet))))
                  (equal type (stype (car (lookup-id id2 aignet))))
                  (not (equal type (const-stype))))
             (equal (equal (stype-count type (cdr (lookup-id id1 aignet)))
                           (stype-count type (cdr (lookup-id id2 aignet))))
                    (nat-equiv id1 id2)))
    :hints(("Goal" :in-theory (enable lookup-id
                                      stype-count
                                      aignet-idp)))
    :otf-flg t)

  (defthm stype-ids-unique
    (implies (and (< (nfix n1) (stype-count stype aignet))
                  (< (nfix n2) (stype-count stype aignet)))
             (equal (equal (node-count (lookup-stype n1 stype aignet))
                           (node-count (lookup-stype n2 stype aignet)))
                    (nat-equiv n1 n2)))
    :hints(("Goal" :in-theory (enable lookup-stype
                                      stype-count))))

  (defthm stype-ids-unique-cdr
    (implies (and (< (nfix n1) (stype-count stype aignet))
                  (< (nfix n2) (stype-count stype aignet)))
             (equal (equal (node-count (cdr (lookup-stype n1 stype aignet)))
                           (node-count (cdr (lookup-stype n2 stype aignet))))
                    (nat-equiv n1 n2)))
    :hints(("Goal" :in-theory (e/d (lookup-stype-in-bounds
                                    node-count)
                                   (stype-ids-unique))
            :use ((:instance stype-ids-unique)))))

  (defthm lookup-reg->nxsts-unique
    (implies (and (consp (lookup-reg->nxst n1 aignet))
                  (consp (lookup-reg->nxst n2 aignet)))
             (equal (equal (node-count (lookup-reg->nxst n1 aignet))
                           (node-count (lookup-reg->nxst n2 aignet)))
                    (nat-equiv n1 n2)))
    :hints(("Goal" :in-theory (enable lookup-reg->nxst))))
  

  (defthm lookup-stype-of-stype-count-match
    (implies (and (bind-free (match-equiv-or-refinement
                              'nat-equiv 'count '(stype-count stype (cdr orig))
                              mfc state)
                             (orig))
                  (nat-equiv count (stype-count stype (cdr orig)))
                  (aignet-extension-p new orig)
                  (equal (stype (car orig)) (stype-fix stype))
                  (not (equal (stype-fix stype) (const-stype))))
             (equal (lookup-stype count stype new)
                    orig))
    :hints(("Goal" :in-theory (disable nat-equiv)))))


(defsection aignet-lit-listp

  (defun aignet-lit-listp (x aignet)
    (declare (xargs :stobjs aignet
                    :guard (lit-listp x)))
    (if (atom x)
        (eq x nil)
      (and (fanin-litp (car x) aignet)
           (aignet-lit-listp (cdr x) aignet)))))


(defsection aignet-extension-p
  :short "Predicate that says that one aignet is the result of building some new
nodes onto another aignet"
  :long "<p>Pretty much every aignet-modifying function produces an extension of
its input.  Net-extension-p is a transitive, reflexive relation that implies a
whole slew of useful things.  The most basic is that any ID of the original
aignet is an ID of the new aignet, and the node of that ID is the same in both aignets
-- this is just a reading of the definition.  But this implies, for example,
that the evaluations of nodes existing in the first are the same as their
evaluations in the second.</p>

<p>Rewrite rules using aignet-extension-p are a little odd.  For example, suppose we
want a rewrite rule just based on the definition, e.g.,
<code>
 (implies (and (aignet-extension-p new-aignet orig-aignet)
               (aignet-idp id orig-aignet))
          (equal (nth-node id new-aignet)
                 (nth-node id orig-aignet)))
</code>
This isn't a very good rewrite rule because it has to match the free variable
orig-aignet.  However, we can make it much better with a bind-free strategy.
We'll check the syntax of new-aignet to see if it is a call of a
aignet-updating function.  Then, we'll use the aignet input of that function as the
binding for orig-aignet.</p>
"

  ;; (defthmd aignet-extension-p-transitive
  ;;   (implies (and (aignet-extension-p aignet2 aignet1)
  ;;                 (aignet-extension-p aignet3 aignet2))
  ;;            (aignet-extension-p aignet3 aignet1)))

  (defun simple-search-type-alist (term typ type-alist unify-subst)
    (declare (xargs :mode :program))
    (cond ((endp type-alist)
           (mv nil unify-subst))
          ((acl2::ts-subsetp (cadr (car type-alist)) typ)
           (mv-let (ans unify-subst)
             (acl2::one-way-unify1 term (car (car type-alist)) unify-subst)
             (if ans
                 (mv t unify-subst)
               ;; note: one-way-unify1 is a no-change-loser so unify-subst is
               ;; unchanged below
               (simple-search-type-alist term typ (cdr type-alist)
                                         unify-subst))))
          (t (simple-search-type-alist term typ (cdr type-alist) unify-subst))))


  ;; Additional possible strategic thing: keep aignet-modifying functions that
  ;; don't produce an extension in a table and don't bind their inputs.
  (defun find-prev-stobj-binding (new-term state)
    (declare (xargs :guard (pseudo-termp new-term)
                    :stobjs state
                    :mode :program))
    (b* (((mv valnum function args)
          (case-match new-term
            (('mv-nth ('quote valnum) (function . args) . &)
             (mv (and (symbolp function) valnum) function args))
            ((function . args)
             (mv (and (symbolp function) 0) function args))
            (& (mv nil nil nil))))
         ((unless valnum) (mv nil nil))
         ((when (and (eq function 'cons)
                     (int= valnum 0)))
          ;; special case for update-nth.
          (mv t (nth 1 args)))
         (w (w state))
         (stobjs-out (acl2::stobjs-out function w))
         (formals (acl2::formals function w))
         (stobj-out (nth valnum stobjs-out))
         ((unless stobj-out) (mv nil nil))
         (pos (position stobj-out formals))
         ((unless pos) (mv nil nil)))
      (mv t (nth pos args))))

  (defun iterate-prev-stobj-binding (n new-term state)
    (declare (xargs :guard (and (pseudo-termp new-term)
                                (natp n))
                    :stobjs state
                    :mode :program))
    (if (zp n)
        new-term
      (mv-let (ok next-term)
        (find-prev-stobj-binding new-term state)
        (if ok
            (iterate-prev-stobj-binding (1- n) next-term state)
          new-term))))

  (defun prev-stobj-binding (new-term prev-var iters mfc state)
    (declare (xargs :guard (and (pseudo-termp new-term)
                                (symbolp prev-var))
                    :stobjs state
                    :mode :program)
             (ignore mfc))
    (let ((prev-term (iterate-prev-stobj-binding iters new-term state)))
      (if (equal new-term prev-term)
          `((do-not-use-this-long-horrible-variable
             . do-not-use-this-long-horrible-variable))
        `((,prev-var . ,prev-term)))))

  (defmacro aignet-extension-binding (&key (new 'new)
                                           (orig 'orig)
                                           (iters '1))
    `(and (bind-free (prev-stobj-binding ,new ',orig ',iters mfc state))
          (aignet-extension-p ,new ,orig)
          (syntaxp (not (subtermp ,new ,orig)))))

  (defthm aignet-extension-p-transitive-rw
    (implies (and (aignet-extension-binding :new aignet3 :orig aignet2)
                  (aignet-extension-p aignet2 aignet1))
             (aignet-extension-p aignet3 aignet1))
    :hints(("Goal" :in-theory (enable aignet-extension-p-transitive))))

  ;; already has inverse
  (defthm aignet-extension-simplify-lookup-id
    (implies (and (aignet-extension-binding)
                  (aignet-idp id orig))
             (equal (lookup-id id new)
                    (lookup-id id orig))))

  (defthm aignet-extension-simplify-lookup-stype
    (implies (and (aignet-extension-binding)
                  (consp (lookup-stype n stype orig)))
             (equal (lookup-stype n stype new)
                    (lookup-stype n stype orig)))
    :hints(("Goal" :in-theory (enable lookup-stype
                                      aignet-extension-p))))

  (defthm aignet-extension-simplify-lookup-stype-when-counts-same
    (implies (and (aignet-extension-binding)
                  (equal (stype-count stype new)
                         (stype-count stype orig)))
             (equal (lookup-stype n stype new)
                    (lookup-stype n stype orig)))
    :hints(("Goal" :in-theory (enable aignet-extension-p
                                      lookup-stype))))

  (defthm aignet-extension-simplify-lookup-stype-inverse
    (implies (and (aignet-extension-bind-inverse)
                  (consp (lookup-stype n stype orig)))
             (equal (lookup-stype n stype orig)
                    (lookup-stype n stype new))))

  (defthm aignet-extension-simplify-aignet-idp
    (implies (and (aignet-extension-binding)
                  (aignet-idp id orig))
             (aignet-idp id new)))

  (defthm aignet-extension-simplify-aignet-litp
    (implies (and (aignet-extension-binding)
                  (aignet-litp lit orig))
             (aignet-litp lit new)))

  (defthm aignet-extension-implies-aignet-lit-listp
    (implies (and (aignet-extension-binding)
                  (aignet-lit-listp lits orig))
             (aignet-lit-listp lits new)))

  (defthm aignet-extension-implies-node-count-gte
    (implies (aignet-extension-binding)
             (<= (node-count orig) (node-count new)))
    :rule-classes ((:linear :trigger-terms ((node-count new)))))

  (defthm aignet-extension-implies-stype-count-gte
    (implies (aignet-extension-binding)
             (<= (stype-count stype orig)
                 (stype-count stype new)))
    :rule-classes ((:linear :trigger-terms ((stype-count stype new)))))

  (defthmd aignet-extension-p-implies-consp
    (implies (and (aignet-extension-binding)
                  (consp orig))
             (consp new))
    :hints(("Goal" :in-theory (enable aignet-extension-p)))))

(defsection preservation-thms
  (acl2::def-stobj-preservation-macros
   :name aignet
   :default-stobjname aignet
   :templates aignet-preservation-templates
   :history aignet-preservation-history)

  (add-aignet-preservation-thm
   aignet-extension-p
   :body `(aignet-extension-p ,new-stobj ,orig-stobj)
   :hints `(,@expand/induct-hints))

  (add-aignet-preservation-thm
   aignet-nodes-ok
   :body `(implies (aignet-nodes-ok ,orig-stobj)
                   (aignet-nodes-ok ,new-stobj))
   :hints expand/induct-hints))


(local (defthm car-nonnil-forward-to-consp
         (implies (not (equal (car x) nil))
                  (consp x))
         :rule-classes ((:forward-chaining :trigger-terms ((car x))))))

(defsection semantics
  (defstobj-clone aignet-invals bitarr :strsubst (("BIT" . "AIGNET-INVAL")))
  (defstobj-clone aignet-regvals bitarr :strsubst (("BIT" . "AIGNET-REGVAL")))

  ; (local (in-theory (enable gate-orderedp co-orderedp)))

  
  (local (in-theory (enable aignet-lit-fix-id-val-linear)))

  ;; ;;; BOZO: Move this into the absstobj definition?  i.e., have
  ;; ;; gate-id->fanin0
  ;; ;; gate-id->fanin1
  ;; ;; co-id->fanin
  ;; ;; do this implicitly?
  ;; (defmacro fanin-lit-fix (lit id aignet)
  ;;   `(mbe :logic (non-exec (aignet-lit-fix ,lit (cdr (lookup-id ,id ,aignet))))
  ;;         :exec ,lit))


  (mutual-recursion
   (defun lit-eval (lit aignet-invals aignet-regvals aignet)
     (declare (xargs :stobjs (aignet aignet-invals aignet-regvals)
                     :guard (and (litp lit)
                                 (fanin-litp lit aignet)
                                 (<= (num-ins aignet) (bits-length aignet-invals))
                                 (<= (num-regs aignet) (bits-length aignet-regvals)))
                     :measure (acl2::two-nats-measure (lit-id lit) 1)
                     :verify-guards nil))
     (b-xor (id-eval (lit-id lit) aignet-invals aignet-regvals aignet)
            (lit-neg lit)))

   (defun eval-and-of-lits (lit1 lit2 aignet-invals aignet-regvals aignet)
     (declare (xargs :stobjs (aignet aignet-invals aignet-regvals)
                     :guard (and (litp lit1) (fanin-litp lit1 aignet)
                                 (litp lit2) (fanin-litp lit2 aignet)
                                 (<= (num-ins aignet) (bits-length aignet-invals))
                                 (<= (num-regs aignet) (bits-length
                                                        aignet-regvals)))
                     :measure (acl2::two-nats-measure
                               (max (lit-id lit1)
                                    (lit-id lit2))
                               2)))
    (b-and (lit-eval lit1 aignet-invals aignet-regvals aignet)
           (lit-eval lit2 aignet-invals aignet-regvals aignet)))

   (defun id-eval (id aignet-invals aignet-regvals aignet)
     (declare (xargs :stobjs (aignet aignet-invals aignet-regvals)
                     :guard (and (natp id) (id-existsp id aignet)
                                 (<= (num-ins aignet) (bits-length aignet-invals))
                                 (<= (num-regs aignet) (bits-length aignet-regvals)))
                     :measure (acl2::two-nats-measure id 0)
                     :hints(("Goal" :in-theory (enable aignet-idp)))))
     (b* (((unless (mbt (id-existsp id aignet)))
           ;; out-of-bounds IDs are false
           0)
          (type (id->type id aignet)))
       (aignet-case
        type
        :gate (b* ((f0 (gate-id->fanin0 id aignet))
                   (f1 (gate-id->fanin1 id aignet)))
                (mbe :logic (eval-and-of-lits
                             f0 f1 aignet-invals aignet-regvals aignet)
                     :exec (b-and (b-xor (id-eval (lit-id f0)
                                                  aignet-invals aignet-regvals aignet)
                                         (lit-neg f0))
                                  (b-xor (id-eval (lit-id f1)
                                                  aignet-invals aignet-regvals
                                                  aignet)
                                         (lit-neg f1)))))
        :in    (if (int= (io-id->regp id aignet) 1)
                   (get-bit (io-id->ionum id aignet) aignet-regvals)
                 (get-bit (io-id->ionum id aignet) aignet-invals))
        :out (b* ((f (co-id->fanin id aignet)))
               (lit-eval f aignet-invals aignet-regvals aignet))
        :const 0))))

  (in-theory (disable id-eval lit-eval eval-and-of-lits))
  (local (in-theory (enable id-eval lit-eval eval-and-of-lits)))

  (defun-nx id-eval-ind (id aignet)
    (declare (xargs :measure (nfix id)
                    :hints(("Goal" :in-theory (enable aignet-idp)))))
    (b* (((unless (mbt (aignet-idp id aignet)))
          ;; out-of-bounds IDs are false
          0)
         (type (id->type id aignet)))
      (aignet-case
       type
       :gate (b* ((f0 (gate-id->fanin0 id aignet))
                   (f1 (gate-id->fanin1 id aignet)))
                (list
                 (id-eval-ind (lit-id f0) aignet)
                 (id-eval-ind (lit-id f1) aignet)))
       :in    nil
       :out (b* ((f (co-id->fanin id aignet)))
              (id-eval-ind (lit-id f) aignet))
       :const 0)))

  (defcong nat-equiv equal (id-eval id invals regvals aignet) 1
    :hints (("goal" :expand ((id-eval id invals regvals aignet)
                             (id-eval nat-equiv invals regvals aignet)))))

  (defcong bits-equiv equal (id-eval id invals regvals aignet) 2
    :hints (("goal" :induct (id-eval-ind id aignet)
             :expand ((:free (invals regvals)
                       (id-eval id invals regvals aignet))))))

  (defcong bits-equiv equal (id-eval id invals regvals aignet) 3
    :hints (("goal" :induct (id-eval-ind id aignet)
             :expand ((:free (invals regvals)
                       (id-eval id invals regvals aignet))))))

  (defcong list-equiv equal (id-eval id invals regvals aignet) 4
    :hints (("goal" :induct (id-eval-ind id aignet)
             :expand ((:free (aignet)
                       (id-eval id invals regvals aignet))))))

  (defcong bits-equiv equal (lit-eval lit invals regvals aignet) 2
    :hints (("goal"
             :expand ((:free (invals regvals)
                       (lit-eval lit invals regvals aignet))))))

  (defcong bits-equiv equal (lit-eval lit invals regvals aignet) 3
    :hints (("goal"
             :expand ((:free (invals regvals)
                       (lit-eval lit invals regvals aignet))))))

  (defcong lit-equiv equal (lit-eval lit invals regvals aignet) 1
    :hints (("goal" :expand ((lit-eval lit invals regvals aignet)
                             (lit-eval lit-equiv invals regvals
                                       aignet)))))

  (defcong list-equiv equal (lit-eval lit invals regvals aignet) 4
    :hints (("goal"
             :expand ((:free (aignet)
                       (lit-eval lit invals regvals aignet))))))

  (defcong bits-equiv equal
    (eval-and-of-lits lit1 lit2 invals regvals aignet) 3
    :hints (("goal"
             :expand ((:free (invals regvals)
                       (eval-and-of-lits lit1 lit2 invals regvals
                                         aignet))))))

  (defcong bits-equiv equal
    (eval-and-of-lits lit1 lit2 invals regvals aignet) 4
    :hints (("goal"
             :expand ((:free (invals regvals)
                       (eval-and-of-lits lit1 lit2 invals regvals
                                         aignet))))))

  (defcong lit-equiv equal
    (eval-and-of-lits lit1 lit2 invals regvals aignet) 1
    :hints (("goal"
             :expand ((:free (lit1)
                       (eval-and-of-lits lit1 lit2 invals regvals
                                         aignet))))))

  (defcong lit-equiv equal
    (eval-and-of-lits lit1 lit2 invals regvals aignet) 2
    :hints (("goal"
             :expand ((:free (lit2)
                       (eval-and-of-lits lit1 lit2 invals regvals
                                         aignet))))))

  (defcong list-equiv equal
    (eval-and-of-lits lit1 lit2 invals regvals aignet) 5
    :hints (("goal"
             :expand ((:free (aignet)
                       (eval-and-of-lits lit1 lit2 invals regvals
                                         aignet))))))


  (flag::make-flag lit/id-eval-flag lit-eval
                   :flag-mapping ((lit-eval . lit)
                                  (id-eval . id)
                                  (eval-and-of-lits . and))
                   :hints(("Goal" :in-theory (enable aignet-idp))))

  (defthm bitp-of-lit-eval
    (bitp (lit-eval lit invals regvals aignet))
    :hints (("goal" :expand (lit-eval lit invals regvals aignet))))

  (defthm bitp-of-id-eval
    (bitp (id-eval id invals regvals aignet))
    :hints (("goal" :expand (id-eval id invals regvals aignet))))

  (defthm bitp-of-eval-and
    (bitp (eval-and-of-lits lit1 lit2 invals regvals aignet))
    :hints (("goal" :expand (eval-and-of-lits lit1 lit2 invals
                                              regvals aignet))))


  (defthm-lit/id-eval-flag
    (defthm id-eval-preserved-by-extension
      (implies (and (aignet-extension-binding :orig aignet)
                    (aignet-idp id aignet))
               (equal (id-eval id invals regvals new)
                      (id-eval id invals regvals aignet)))
      :hints ((and stable-under-simplificationp
                   '(:expand ((:free (aignet) (id-eval id invals regvals aignet))))))
      :flag id)
    (defthm lit-eval-preserved-by-extension
      (implies (and (aignet-extension-binding :orig aignet)
                    (aignet-idp (lit-id lit) aignet))
               (equal (lit-eval lit invals regvals new)
                      (lit-eval lit invals regvals aignet)))
      :flag lit)
    (defthm eval-and-preserved-by-extension
      (implies (and (aignet-extension-binding :orig aignet)
                    (aignet-idp (lit-id lit1) aignet)
                    (aignet-idp (lit-id lit2) aignet))
               (equal (eval-and-of-lits lit1 lit2 invals regvals new)
                      (eval-and-of-lits lit1 lit2 invals regvals aignet)))
      :flag and))

  (defthm id-eval-preserved-by-extension-inverse
    (implies (and (aignet-extension-bind-inverse :orig aignet)
                  (aignet-idp id aignet))
             (equal (id-eval id invals regvals aignet)
                    (id-eval id invals regvals new)))
    :hints (("goal" :use id-eval-preserved-by-extension)))

  (defthm lit-eval-preserved-by-extension-inverse
    (implies (and (aignet-extension-bind-inverse)
                  (aignet-idp (lit-id lit) orig))
             (equal (lit-eval lit invals regvals orig)
                    (lit-eval lit invals regvals new))))

  (defthm eval-and-preserved-by-extension-inverse
    (implies (and (aignet-extension-bind-inverse)
                  (aignet-idp (lit-id lit1) orig)
                  (aignet-idp (lit-id lit2) orig))
             (equal (eval-and-of-lits lit1 lit2 invals regvals orig)
                    (eval-and-of-lits lit1 lit2 invals regvals new))))


  (defthm aignet-idp-of-co-node->fanin-when-aignet-nodes-ok
    (implies (and (aignet-nodes-ok aignet)
                  (equal (id->type id aignet) (out-type))
                  (aignet-extension-p aignet2 (cdr (lookup-id id aignet))))
             (aignet-idp (lit-id (co-node->fanin (car (lookup-id id aignet))))
                         aignet2))
    :hints(("Goal" :in-theory (enable aignet-nodes-ok lookup-id))))

  (defthm aignet-idp-of-gate-node->fanins-when-aignet-nodes-ok
    (implies (and (aignet-nodes-ok aignet)
                  (equal (id->type id aignet) (gate-type))
                  (aignet-extension-p aignet2 (cdr (lookup-id id aignet))))
             (and (aignet-idp (lit-id (gate-node->fanin0 (car (lookup-id id aignet))))
                              aignet2)
                  (aignet-idp (lit-id (gate-node->fanin1 (car (lookup-id id aignet))))
                              aignet2)))
    :hints(("Goal" :in-theory (enable aignet-nodes-ok lookup-id))))

  (local (include-book "centaur/aignet/bit-lemmas" :dir :system))

  (defthm lit-eval-of-mk-lit-of-lit-id
    (equal (lit-eval (mk-lit (lit-id x) neg) invals regvals aignet)
           (b-xor (b-xor neg (lit-neg x))
                  (lit-eval x invals regvals aignet))))

  (local (defthm lit-eval-of-mk-lit-0
           (equal (lit-eval (mk-lit 0 neg) invals regvals aignet)
                  (bfix neg))))

  (defthm lit-eval-of-aignet-lit-fix
    (equal (lit-eval (aignet-lit-fix x aignet) invals regvals aignet)
           (lit-eval x invals regvals aignet))
    :hints(("Goal" :in-theory (e/d (aignet-lit-fix)
                                   (lit-eval))
            :induct (aignet-lit-fix x aignet)
            :expand ((lit-eval x invals regvals aignet)))))

  (defthm lit-eval-of-aignet-lit-fix-extension
    (implies (aignet-extension-p aignet2 aignet)
             (equal (lit-eval (aignet-lit-fix x aignet) invals regvals aignet2)
                    (lit-eval x invals regvals aignet))))

  (defthm id-eval-of-aignet-lit-fix
    (equal (id-eval (lit-id (aignet-lit-fix x aignet)) invals regvals aignet)
           (b-xor (b-xor (lit-neg x) (lit-neg (aignet-lit-fix x aignet)))
                  (id-eval (lit-id x) invals regvals aignet)))
    :hints (("goal" :use lit-eval-of-aignet-lit-fix
             :in-theory (e/d (lit-eval b-xor)
                             (lit-eval-of-aignet-lit-fix
                              lit-eval-of-aignet-lit-fix-extension
                              id-eval)))))

  (defthm eval-and-of-lits-of-aignet-lit-fix-1
    (equal (eval-and-of-lits (aignet-lit-fix x aignet) y invals regvals aignet)
           (eval-and-of-lits x y invals regvals aignet))
    :hints(("Goal" :in-theory (disable lit-eval))))

  (defthm eval-and-of-lits-of-aignet-lit-fix-1-extension
    (implies (and (aignet-extension-p aignet2 aignet)
                  (aignet-idp (lit-id y) aignet))
             (equal (eval-and-of-lits (aignet-lit-fix x aignet) y invals regvals aignet2)
                    (eval-and-of-lits x y invals regvals aignet))))

  (defthm eval-and-of-lits-of-aignet-lit-fix-2
    (equal (eval-and-of-lits y (aignet-lit-fix x aignet) invals regvals aignet)
           (eval-and-of-lits y x invals regvals aignet))
    :hints(("Goal" :in-theory (disable lit-eval))))

  (defthm eval-and-of-lits-of-aignet-lit-fix-2-extension
    (implies (and (aignet-extension-p aignet2 aignet)
                  (aignet-idp (lit-id y) aignet))
             (equal (eval-and-of-lits y (aignet-lit-fix x aignet) invals regvals aignet2)
                    (eval-and-of-lits y x invals regvals aignet))))

  (in-theory (disable id-eval-of-aignet-lit-fix
                      lit-eval-of-aignet-lit-fix
                      lit-eval-of-aignet-lit-fix-extension
                      eval-and-of-lits-of-aignet-lit-fix-1
                      eval-and-of-lits-of-aignet-lit-fix-1-extension
                      eval-and-of-lits-of-aignet-lit-fix-2
                      eval-and-of-lits-of-aignet-lit-fix-2-extension))


  (verify-guards lit-eval)

  (defun lit-eval-list (x aignet-invals aignet-regvals aignet)
    (declare (xargs :stobjs (aignet aignet-invals aignet-regvals)
                    :guard (and (lit-listp x)
                                (aignet-lit-listp x aignet)
                                (<= (num-ins aignet) (bits-length aignet-invals))
                                (<= (num-regs aignet) (bits-length aignet-regvals)))))
    (if (atom x)
        nil
      (cons (lit-eval (car x) aignet-invals aignet-regvals aignet)
            (lit-eval-list (cdr x) aignet-invals aignet-regvals aignet))))

  (defthm lit-eval-list-preserved-by-extension
    (implies (and (aignet-extension-binding)
                  (aignet-lit-listp lits orig))
             (equal (lit-eval-list lits aignet-invals aignet-regvals new)
                    (lit-eval-list lits aignet-invals aignet-regvals orig))))

  (defthm lit-eval-list-preserved-by-extension-inverse
    (implies (and (aignet-extension-bind-inverse)
                  (aignet-lit-listp lits orig))
             (equal (lit-eval-list lits aignet-invals aignet-regvals orig)
                    (lit-eval-list lits aignet-invals aignet-regvals new))))


  (defthm id-eval-of-aignet-add-gate-new
    (b* ((new-id (+ 1 (node-count aignet)))
         (aignet1 (cons (gate-node f0 f1) aignet)))
      (equal (id-eval new-id invals regvals aignet1)
             (eval-and-of-lits f0 f1 invals regvals aignet)))
    :hints(("Goal" :expand ((:free (id aignet1)
                             (id-eval id invals regvals aignet1)))
            :do-not-induct t
            :in-theory (e/d (aignet-idp
                             eval-and-of-lits-of-aignet-lit-fix-1
                             eval-and-of-lits-of-aignet-lit-fix-2-extension)
                            (eval-and-of-lits)))))

  (defthm id-eval-of-0
    (equal (id-eval 0 invals regvals aignet) 0))

  (defthm lit-eval-of-0-and-1
    (and (equal (lit-eval 0 invals regvals aignet) 0)
         (equal (lit-eval 1 invals regvals aignet) 1))))

(defsection semantics-seq
  (local (in-theory (disable acl2::bfix-when-not-1
                             acl2::nfix-when-not-natp)))
  (local (in-theory (enable acl2::make-list-ac-redef)))

  (acl2::def2darr aignet-frames
                  :prefix frames
                  :elt-type bit
                  :elt-typep bitp
                  :default-elt 0
                  :elt-fix acl2::bfix
                  :elt-guard (bitp x))

  (defstobj-clone aignet-initsts bitarr :strsubst (("BIT" . "AIGNET-INITSTS")))

  (local (in-theory (enable aignet-lit-fix-id-val-linear)))

  (mutual-recursion
   (defun lit-eval-seq (k lit aignet-frames aignet-initsts aignet)
     (declare (xargs :stobjs (aignet aignet-frames aignet-initsts)
                     :guard (and (litp lit) (fanin-litp lit aignet)
                                 (natp k)
                                 (< k (frames-nrows aignet-frames))
                                 (<= (num-ins aignet) (frames-ncols aignet-frames))
                                 (<= (num-regs aignet) (bits-length aignet-initsts)))
                     :measure (acl2::nat-list-measure
                               (list k (lit-id lit) 1))
                     :verify-guards nil))
     (b-xor (id-eval-seq k (lit-id lit) aignet-frames aignet-initsts aignet)
            (lit-neg lit)))

   (defun eval-and-of-lits-seq (k lit1 lit2 aignet-frames aignet-initsts aignet)
     (declare (xargs :stobjs (aignet aignet-frames aignet-initsts)
                     :guard (and (litp lit1) (fanin-litp lit1 aignet)
                                 (litp lit2) (fanin-litp lit2 aignet)
                                 (natp k)
                                 (< k (frames-nrows aignet-frames))
                                 (<= (num-ins aignet) (frames-ncols aignet-frames))
                                 (<= (num-regs aignet) (bits-length aignet-initsts)))
                     :measure (acl2::nat-list-measure
                               (list k
                                     (max (lit-id lit1)
                                          (lit-id lit2))
                                     2))
                     :verify-guards nil))
     (b-and (lit-eval-seq k lit1 aignet-frames aignet-initsts aignet)
            (lit-eval-seq k lit2 aignet-frames aignet-initsts aignet)))

   (defun id-eval-seq (k id aignet-frames aignet-initsts aignet)
     (declare (xargs :stobjs (aignet aignet-frames aignet-initsts)
                     :guard (and (natp id) (id-existsp id aignet)
                                 (natp k)
                                 (< k (frames-nrows aignet-frames))
                                 (<= (num-ins aignet) (frames-ncols aignet-frames))
                                 (<= (num-regs aignet) (bits-length aignet-initsts)))
                     :measure (acl2::nat-list-measure
                               (list k id 0))))
     (b* (((unless (mbt (id-existsp id aignet)))
           ;; out-of-bounds IDs are false
           0)
          (type (id->type id aignet)))
       (aignet-case
        type
        :gate (b* ((f0 (gate-id->fanin0 id aignet))
                   (f1 (gate-id->fanin1 id aignet)))
                (mbe :logic (eval-and-of-lits-seq
                             k f0 f1 aignet-frames aignet-initsts aignet)
                     :exec (b-and (b-xor (id-eval-seq k (lit-id f0)
                                                      aignet-frames
                                                      aignet-initsts aignet)
                                         (lit-neg f0))
                                  (b-xor (id-eval-seq k (lit-id f1)
                                                      aignet-frames
                                                      aignet-initsts aignet)
                                         (lit-neg f1)))))
        :in    (let ((ionum (io-id->ionum id aignet)))
                 (if (int= (io-id->regp id aignet) 1)
                     (if (zp k)
                         (get-bit ionum aignet-initsts)
                       (id-eval-seq (1- k)
                                    (reg-id->nxst id aignet)
                                    aignet-frames aignet-initsts aignet))
                   (frames-get2 k ionum aignet-frames)))
        :out (b* ((f (co-id->fanin id aignet)))
               (lit-eval-seq
                k f aignet-frames aignet-initsts aignet))
        :const 0))))

  (in-theory (disable id-eval-seq lit-eval-seq eval-and-of-lits-seq))
  (local (in-theory (enable id-eval-seq lit-eval-seq eval-and-of-lits-seq)))


  (defun-nx id-eval-seq-ind (k id aignet)
    (declare (xargs :measure (acl2::two-nats-measure k id)))
    (b* (((unless (mbt (aignet-idp id aignet)))
          ;; out-of-bounds IDs are false
          0)
         (type (id->type id aignet)))
      (aignet-case
        type
        :gate (b* ((f0 (gate-id->fanin0 id aignet))
                   (f1 (gate-id->fanin1 id aignet)))
                (list
                 (id-eval-seq-ind
                  k (lit-id f0) aignet)
                 (id-eval-seq-ind
                  k (lit-id f1) aignet)))
        :in     (if (int= (io-id->regp id aignet) 1)
                    (if (zp k)
                        0
                      (id-eval-seq-ind
                       (1- k) (reg-id->nxst id aignet) aignet))
                  0)
        :out  (b* ((f (co-id->fanin id aignet)))
                (id-eval-seq-ind
                 k (lit-id f) aignet))
        :const 0)))

  (defcong nat-equiv equal (id-eval-seq k id frames initvals aignet) 1
    :hints (("goal" :induct (id-eval-seq-ind k id aignet))))

  (defcong bits-equiv equal (id-eval-seq k id frames initvals aignet) 4
    :hints (("goal" :induct (id-eval-seq-ind k id aignet))))

  (defcong nat-equiv equal (id-eval-seq k id frames initvals aignet) 2
    :hints (("goal" :induct (id-eval-seq-ind k id aignet)
             :expand ((id-eval-seq k id frames initvals aignet)
                      (id-eval-seq k nat-equiv frames initvals aignet)))))

  (defcong list-equiv equal (id-eval-seq k id frames initvals aignet) 5
    :hints (("goal" :induct (id-eval-seq-ind k id aignet)
             :in-theory (disable id-eval-seq lit-eval-seq))
            (and stable-under-simplificationp
                 '(:expand ((:free (k aignet)
                             (id-eval-seq k id frames initvals aignet))
                            (:free (lit aignet)
                             (lit-eval-seq k lit frames initvals aignet)))))))

  (defcong nat-equiv equal (lit-eval-seq k lit frames initvals aignet) 1
    :hints (("goal" :expand ((lit-eval-seq k lit frames initvals aignet)))))
  (defcong bits-equiv equal (lit-eval-seq k lit frames initvals aignet) 4
    :hints (("goal" :expand ((lit-eval-seq k lit frames initvals aignet)))))
  (defcong lit-equiv equal (lit-eval-seq k lit frames initvals aignet) 2
    :hints (("goal" :expand ((lit-eval-seq k lit frames initvals aignet)))))
  (defcong list-equiv equal (lit-eval-seq k lit frames initvals aignet) 5
    :hints (("goal" :expand ((:free (aignet)
                              (lit-eval-seq k lit frames initvals aignet))))))

  (defcong nat-equiv equal (eval-and-of-lits-seq k lit1 lit2 frames initvals aignet) 1
    :hints (("goal" :expand ((eval-and-of-lits-seq k lit1 lit2 frames initvals aignet)))))
  (defcong bits-equiv equal (eval-and-of-lits-seq k lit1 lit2 frames initvals aignet) 5
    :hints (("goal" :expand ((eval-and-of-lits-seq k lit1 lit2 frames initvals aignet)))))
  (defcong lit-equiv equal (eval-and-of-lits-seq k lit1 lit2 frames initvals aignet) 2
    :hints (("goal" :expand ((eval-and-of-lits-seq k lit1 lit2 frames initvals aignet)))))
  (defcong lit-equiv equal (eval-and-of-lits-seq k lit1 lit2 frames initvals aignet) 3
    :hints (("goal" :expand ((eval-and-of-lits-seq k lit1 lit2 frames initvals aignet)))))
  (defcong list-equiv equal (eval-and-of-lits-seq k lit1 lit2 frames initvals aignet) 6
    :hints (("goal" :expand ((:free (aignet)
                              (eval-and-of-lits-seq k lit1 lit2 frames initvals aignet))))))


  ;; collect up the register input values for a frame
  (defund-nx next-frame-regvals (n k aignet-frames aignet-initsts aignet)
    (declare (xargs :measure (nfix (- (nfix (num-regs aignet))
                                      (nfix n)))))
    (if (zp (- (nfix (num-regs aignet))
               (nfix n)))
        nil
      (update-nth n (id-eval-seq k (reg-id->nxst (regnum->id n aignet) aignet)
                                 aignet-frames aignet-initsts
                                 aignet)
                  (next-frame-regvals (1+ (nfix n)) k aignet-frames
                                      aignet-initsts aignet))))

  (local (in-theory (enable next-frame-regvals)))

  (defcong nat-equiv equal (next-frame-regvals
                            n k aignet-frames aignet-initst aignet) 1)
  (defcong nat-equiv equal (next-frame-regvals
                            n k aignet-frames aignet-initst aignet) 2)
  (defcong bits-equiv equal (next-frame-regvals
                             n k aignet-frames aignet-initst aignet) 4)

  (defthm nth-of-next-frame-regvals
    (implies (and (< (nfix m) (nfix (num-regs aignet)))
                  (<= (nfix n) (nfix m)))
             (equal (nth m (next-frame-regvals n k aignet-frames aignet-initsts aignet))
                    (id-eval-seq k (reg-id->nxst (regnum->id m aignet) aignet)
                                 aignet-frames aignet-initsts aignet)))
    :hints (("goal" :induct (next-frame-regvals n k aignet-frames
                                                aignet-initsts aignet))))

  (defthm bitp-of-id-eval-seq
    (bitp (id-eval-seq k id frames initvals aignet))
    :hints (("goal" :induct (id-eval-seq-ind k id aignet))))

  (defund frame-regvals (k frames initvals aignet)
    (if (zp k)
        initvals
      (next-frame-regvals 0 (1- k) frames initvals aignet)))


  (defthm nth-of-frame-regvals
    (implies (< (nfix m) (num-regs aignet))
             (equal (nth m (frame-regvals k frames initvals aignet))
                    (if (zp k)
                        (nth m initvals)
                      (id-eval-seq
                       (1- k) (reg-id->nxst (regnum->id m aignet) aignet)
                       frames initvals aignet))))
    :hints(("Goal" :in-theory (enable frame-regvals))))
                  
  (local (in-theory (enable id-eval-ind)))

  (defthmd id-eval-seq-in-terms-of-id-eval
    (equal (id-eval-seq k id frames initvals aignet)
           (id-eval id
                    (nth k (cdr frames))
                    (frame-regvals k frames initvals aignet)
                    aignet))
    :hints (("goal" :induct (id-eval-ind id aignet)
             :expand ((:free (k) (id-eval-seq k id frames initvals aignet))
                      (:free (invals regvals)
                       (id-eval id invals regvals aignet))
                      (:free (k lit)
                       (lit-eval-seq k lit invals regvals aignet)))
             :in-theory (e/d (lit-eval
                              eval-and-of-lits)
                             (id-eval-seq
                              id-eval))))))





(defsection comb-equiv
  (defun-sk comb-equiv (aignet aignet2)
    (forall (n invals regvals)
            (and (equal (equal (stype-count (po-stype) aignet)
                               (stype-count (po-stype) aignet2))
                        t)
                 (equal (equal (stype-count (reg-stype) aignet)
                               (stype-count (reg-stype) aignet2))
                        t)
                 (implies (< (nfix n) (stype-count (po-stype) aignet))
                          (equal (equal (id-eval (node-count (lookup-stype n
                                                                           (po-stype)
                                                                           aignet))
                                                 invals regvals aignet)
                                        (id-eval (node-count (lookup-stype n
                                                                           (po-stype)
                                                                           aignet2))
                                                 invals regvals aignet2))
                                 t))
                 (implies (< (nfix n) (stype-count (reg-stype) aignet))
                          (equal (equal (id-eval (node-count
                                                  (lookup-reg->nxst
                                                   (node-count
                                                    (lookup-stype n (reg-stype)
                                                                  aignet))
                                                   aignet))
                                                 invals regvals aignet)
                                        (id-eval (node-count
                                                  (lookup-reg->nxst
                                                   (node-count
                                                    (lookup-stype n (reg-stype)
                                                                  aignet2))
                                                   aignet2))
                                                 invals regvals aignet2))
                                 t))))
    :rewrite :direct)

  (in-theory (disable comb-equiv comb-equiv-necc))

  (local (defthm refl
           (comb-equiv x x)
           :hints(("Goal" :in-theory (enable comb-equiv)))))

  (local
   (defthm symm
     (implies (comb-equiv aignet aignet2)
              (comb-equiv aignet2 aignet))
     :hints ((and stable-under-simplificationp
                  `(:expand (,(car (last clause)))
                    :use ((:instance comb-equiv-necc
                           (n (mv-nth 0 (comb-equiv-witness aignet2 aignet)))
                           (invals (mv-nth 1 (comb-equiv-witness aignet2 aignet)))
                           (regvals (mv-nth 2 (comb-equiv-witness aignet2
                                                                  aignet))))))))))

  (local
   (defthm trans-lemma
     (implies (and (comb-equiv aignet aignet2)
                   (comb-equiv aignet2 aignet3))
              (comb-equiv aignet aignet3))
     :hints ((and stable-under-simplificationp
                  `(:expand (,(car (last clause)))
                    :use ((:instance comb-equiv-necc
                           (n (mv-nth 0 (comb-equiv-witness aignet aignet3)))
                           (invals (mv-nth 1 (comb-equiv-witness aignet aignet3)))
                           (regvals (mv-nth 2 (comb-equiv-witness aignet aignet3))))
                          (:instance comb-equiv-necc
                           (aignet aignet2) (aignet2 aignet3)
                           (n (mv-nth 0 (comb-equiv-witness aignet aignet3)))
                           (invals (mv-nth 1 (comb-equiv-witness aignet aignet3)))
                           (regvals (mv-nth 2 (comb-equiv-witness aignet
                                                                  aignet3))))))))))

  (defequiv comb-equiv))



(defsection seq-equiv
  ;; NOTE: This assumes the initial states of both aignets are all-zero.
  (defun-sk seq-equiv (aignet aignet2)
    (forall (k n inframes)
            (and (equal (equal (stype-count (po-stype) aignet)
                               (stype-count (po-stype) aignet2))
                        t)
                 (implies (< (nfix n) (stype-count (po-stype) aignet))
                          (equal (equal (id-eval-seq k (node-count (lookup-stype n
                                                                                 (po-stype)
                                                                                 aignet))
                                                     inframes nil aignet)
                                        (id-eval-seq k (node-count (lookup-stype n
                                                                                 (po-stype)
                                                                                 aignet2))
                                                     inframes nil aignet2))
                                 t))))
    :rewrite :direct)

  (in-theory (disable seq-equiv seq-equiv-necc))

  (local (defthm refl
           (seq-equiv x x)
           :hints(("Goal" :in-theory (enable seq-equiv)))))

  (local
   (defthm symm
     (implies (seq-equiv aignet aignet2)
              (seq-equiv aignet2 aignet))
     :hints ((and stable-under-simplificationp
                  `(:expand (,(car (last clause)))
                    :use ((:instance seq-equiv-necc
                           (k (mv-nth 0 (seq-equiv-witness aignet2 aignet)))
                           (n (mv-nth 1 (seq-equiv-witness aignet2 aignet)))
                           (inframes (mv-nth 2 (seq-equiv-witness aignet2 aignet))))))))))

  (local
   (defthm trans-lemma
     (implies (and (seq-equiv aignet aignet2)
                   (seq-equiv aignet2 aignet3))
              (seq-equiv aignet aignet3))
     :hints ((and stable-under-simplificationp
                  `(:expand (,(car (last clause)))
                    :use ((:instance seq-equiv-necc
                           (k (mv-nth 0 (seq-equiv-witness aignet aignet3)))
                           (n (mv-nth 1 (seq-equiv-witness aignet aignet3)))
                           (inframes (mv-nth 2 (seq-equiv-witness aignet aignet3))))
                          (:instance seq-equiv-necc
                           (aignet aignet2) (aignet2 aignet3)
                           (k (mv-nth 0 (seq-equiv-witness aignet aignet3)))
                           (n (mv-nth 1 (seq-equiv-witness aignet aignet3)))
                           (inframes (mv-nth 2 (seq-equiv-witness aignet aignet3))))))))))

  (defequiv seq-equiv))