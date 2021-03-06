;; AUTHOR:
;; Shilpi Goel <shigoel@cs.utexas.edu>

(in-package "X86ISA")

;; ======================================================================

(include-book "x86-arith-and-logic-instructions"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))
(include-book "x86-bit-instructions"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))
(include-book "x86-conditional-instructions"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))
(include-book "x86-divide-instructions"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))
(include-book "x86-exchange-instructions"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))
(include-book "x86-jump-and-loop-instructions"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))
(include-book "x86-move-instructions"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))
(include-book "x86-multiply-instructions"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))
(include-book "x86-push-and-pop-instructions"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))
(include-book "x86-rotate-and-shift-instructions"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))
(include-book "x86-segmentation-instructions"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))
(include-book "x86-signextend-instructions"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))
(include-book "x86-string-instructions"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))
(include-book "x86-syscall-instructions"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))
(include-book "x86-subroutine-instructions"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))

;; [Shilpi]: Add FP instructions to their own book.
(include-book "floating-point"
              :ttags (:include-raw :syscall-exec :other-non-det :undef-flg))

(local (include-book "centaur/bitops/ihs-extensions" :dir :system))

;; ======================================================================

(defsection x86-instructions
  :parents (machine)
  )

(defsection one-byte-opcodes
  :parents (x86-instructions)
  )

(defsection two-byte-opcodes
  :parents (x86-instructions)
  )

(defsection fp-opcodes
  :parents (x86-instructions)
  )

(defsection privileged-opcodes
  :parents (x86-instructions)
  )

(defsection x86-instruction-semantics
  :parents (x86-instructions)
  :short "Instruction Semantic Functions"
  :long "<p>The instruction semantic functions have dual roles:</p>

<ol>
 <li>They fetch the instruction's operands, as dictated by the decoded
  components of the instruction \(like the prefixes, SIB byte, etc.\)
  provided as input; these decoded components are provided by our x86
  decoder function @(see x86-fetch-decode-execute).</li>

<li> They contain or act as the functional specification of the
instructions.  For e.g., the functional specification function of the
ADD instruction returns two values: the appropriately truncated sum of
the operands and the modified flags. We do not deal with the x86 state
in these specifications.</li>
</ol>"
  )

;; Misc. instructions not categorized yet into the books included above or not
;; yet placed in their own separate books follow.

;; ======================================================================
;; INSTRUCTION: HLT
;; ======================================================================

;; [Shilpi]: I haven't specified the halt instruction accurately --- halt can
;; be called only in the supervisor mode.  For now, we use the HALT instruction
;; for convenience, e.g., when we want to stop program execution.

(def-inst x86-hlt

  ;; Op/En: NP
  ;; F4

  :parents (one-byte-opcodes)
  :guard-hints (("Goal" :in-theory (e/d (rim08 rim32) ())))

  :returns (x86 x86p :hyp (and (x86p x86)
                               (canonical-address-p temp-rip)))
  :implemented
  (add-to-implemented-opcodes-table 'HLT #xF4 '(:nil nil) 'x86-hlt)

  :body

  (b* ((ctx 'x86-hlt)
       (lock? (equal #.*lock* (prefixes-slice :group-1-prefix prefixes)))
       ((when lock?)
        (!!ms-fresh :lock-prefix prefixes))

       ;; Update the x86 state:

       ;; See p.3-481, Intel Vol. 2A. Instruction pointer is saved.
       ;; "If an interrupt ... is used to resume execution after a HLT
       ;; instruction, the saved instruction pointer points to the instruction
       ;; following the HLT instruction."
       (x86 (!rip temp-rip x86)))
      (!!ms-fresh :legal-halt :hlt)))

;; ======================================================================
;; INSTRUCTION: CMC/CLC/STC/CLD/STD
;; ======================================================================

(def-inst x86-cmc/clc/stc/cld/std

  ;; Op/En: NP
  ;; F5: CMC (CF complemented, all other flags are unaffected)
  ;; F8: CLC (CF cleared, all other flags are unaffected)
  ;; F9: STC (CF set, all other flags are unaffected)
  ;; FC: CLD (DF cleared, all other flags are unaffected)
  ;; FD: STD (DF set, all other flags are unaffected)

  :parents (one-byte-opcodes)
  :guard-hints (("Goal" :in-theory (e/d (rim08 rim32) ())))

  :returns (x86 x86p :hyp (and (x86p x86)
                               (canonical-address-p temp-rip)))
  :implemented
  (progn
    (add-to-implemented-opcodes-table 'CMC #xF5 '(:nil nil)
                                      'x86-cmc/clc/stc/cld/std)
    (add-to-implemented-opcodes-table 'CLC #xF8 '(:nil nil)
                                      'x86-cmc/clc/stc/cld/std)
    (add-to-implemented-opcodes-table 'STC #xF9 '(:nil nil)
                                      'x86-cmc/clc/stc/cld/std)
    (add-to-implemented-opcodes-table 'CLD #xFC '(:nil nil)
                                      'x86-cmc/clc/stc/cld/std)
    (add-to-implemented-opcodes-table 'STD #xFD '(:nil nil)
                                      'x86-cmc/clc/stc/cld/std))

  :body

  (b* ((ctx 'x86-cmc/clc/stc/cld/std)
       (lock? (equal #.*lock* (prefixes-slice :group-1-prefix prefixes)))
       ((when lock?)
        (!!ms-fresh :lock-prefix prefixes))

       (x86 (case opcode
              (#xF5 ;; CMC
               (let* ((cf (the (unsigned-byte 1)
                            (flgi #.*cf* x86)))
                      (not-cf (if (equal cf 1) 0 1)))
                 (!flgi #.*cf* not-cf x86)))
              (#xF8 ;; CLC
               (!flgi #.*cf* 0 x86))
              (#xF9 ;; STC
               (!flgi #.*cf* 1 x86))
              (#xFC ;; CLD
               (!flgi #.*df* 0 x86))
              (otherwise ;; #xFD STD
               (!flgi #.*df* 1 x86))))

       (x86 (!rip temp-rip x86)))
      x86))

;; ======================================================================
;; INSTRUCTION: SAHF
;; ======================================================================

(def-inst x86-sahf

  ;; Opcode: #x9E

  ;; TO-DO@Shilpi: The following instruction is valid in 64-bit mode
  ;; only if the CPUID.80000001H:ECX.LAHF-SAHF[bit0] = 1.

  :parents (one-byte-opcodes)
  :guard-hints (("Goal" :in-theory (e/d (rim08 rim32) ())))

  :returns (x86 x86p :hyp (and (x86p x86)
                               (canonical-address-p temp-rip)))
  :implemented
  (add-to-implemented-opcodes-table 'SAHF #x9E '(:nil nil) 'x86-sahf)

  :body

  (b* ((ctx 'x86-sahf)
       (lock? (equal #.*lock* (prefixes-slice :group-1-prefix prefixes)))
       ((when lock?)
        (!!ms-fresh :lock-prefix prefixes))
       ((the (unsigned-byte 16) ax)
        (mbe :logic (rgfi-size 2 *rax* rex-byte x86)
             :exec (rr16 *rax* x86)))
       ((the (unsigned-byte 8) ah) (ash ax -8))
       ;; Bits 1, 3, and 5 of eflags are unaffected, with the values remaining
       ;; 1, 0, and 0, respectively.
       ((the (unsigned-byte 8) ah) (logand #b11010111 (logior #b10 ah)))
       ;; Update the x86 state:
       (x86 (!rflags ah x86))
       (x86 (!rip temp-rip x86)))
      x86))

;; ======================================================================
;; INSTRUCTION: LAHF
;; ======================================================================

(def-inst x86-lahf

  ;; Opcode: #x9F

  ;; TO-DO@Shilpi: The following instruction is valid in 64-bit mode
  ;; only if the CPUID.80000001H:ECX.LAHF-LAHF[bit0] = 1.

  :parents (one-byte-opcodes)
  :guard-hints (("Goal" :in-theory (e/d (rim08 rim32) ())))

  :returns (x86 x86p :hyp (and (x86p x86)
                               (canonical-address-p temp-rip)))
  :implemented
  (add-to-implemented-opcodes-table 'LAHF #x9F '(:nil nil) 'x86-lahf)

  :body

  (b* ((ctx 'x86-lahf)
       (lock? (equal #.*lock* (prefixes-slice :group-1-prefix prefixes)))
       ((when lock?)
        (!!ms-fresh :lock-prefix prefixes))
       ((the (unsigned-byte 8) ah)
        (logand #xff (the (unsigned-byte 32) (rflags x86))))
       ((the (unsigned-byte 16) ax)
        (mbe :logic (rgfi-size 2 *rax* rex-byte x86)
             :exec (rr16 *rax* x86)))
       ((the (unsigned-byte 16) ax) (logior (logand #xff00 ax) ah))
       ;; Update the x86 state:
       (x86 (mbe :logic (!rgfi-size 2 *rax* ax rex-byte x86)
                 :exec (wr16 *rax* ax x86)))
       (x86 (!rip temp-rip x86)))
      x86))

;; ======================================================================
;; INSTRUCTION: RDRAND
;; ======================================================================

(def-inst x86-rdrand

  ;; 0F C7:
  ;; Opcode Extensions:
  ;; Bits 5,4,3 of the ModR/M byte (reg): 110
  ;; Bits 7,6 of the ModR/M byte (mod):    11

  :parents (two-byte-opcodes)

  :returns (x86 x86p :hyp (and (x86p x86)
                               (canonical-address-p temp-rip))
                :hints (("Goal" :in-theory (e/d (hw_rnd_gen
                                                 hw_rnd_gen-logic)
                                                (force (force))))))
  :implemented
  (add-to-implemented-opcodes-table 'RDRAND #x0FC7 '(:reg 6 :mod 3)
                                    'x86-rdrand)

  :long
  "<p>Note from the Intel Manual (Sept. 2013, Vol. 1, Section 7.3.17):</p>

<p><em>Under heavy load, with multiple cores executing RDRAND in
parallel, it is possible, though unlikely, for the demand of random
numbers by software processes or threads to exceed the rate at which
the random number generator hardware can supply them. This will lead
to the RDRAND instruction returning no data transitorily. The RDRAND
instruction indicates the occurrence of this rare situation by
clearing the CF flag.</em></p>

<p>See <a
href='http://software.intel.com/en-us/articles/intel-digital-random-number-generator-drng-software-implementation-guide/'>Intel's
Digital Random Number Generator Guide</a> for more details.</p>"

  :body

  (b* ((ctx 'x86-rdrand)
       (reg (the (unsigned-byte 3) (mrm-reg  modr/m)))

       (lock? (equal #.*lock* (prefixes-slice :group-1-prefix prefixes)))
       (rep (prefixes-slice :group-2-prefix prefixes))
       (rep-p (or (equal #.*repe* rep)
                  (equal #.*repne* rep)))
       ((when (or lock? rep-p))
        (!!ms-fresh :lock-prefix-or-rep-p prefixes))
       (p3? (equal #.*operand-size-override*
                   (prefixes-slice :group-3-prefix prefixes)))
       ((the (integer 1 8) operand-size)
        (if p3?
            2
          (if (logbitp #.*w* rex-byte)
              8
            4)))
       ((mv rand-and-cf x86)
        (HW_RND_GEN operand-size x86))

       ;; (- (cw "~%~%HW_RND_GEN: If RDRAND does not return the result you ~
       ;;         expected (or returned an error), then you might want to check whether these ~
       ;;         books were compiled using x86isa_exec set to t. See ~
       ;;         :doc build-instructions.~%~%"))

       ((when (ms x86))
        (!!ms-fresh :x86-rdrand (ms x86)))
       ((when (or (not (consp rand-and-cf))
                  (not (unsigned-byte-p (ash operand-size 3) (car rand-and-cf)))
                  (not (unsigned-byte-p 1 (cdr rand-and-cf)))))
        (!!ms-fresh :x86-rdrand-ill-formed-outputs (ms x86)))

       (rand (car rand-and-cf))
       (cf (cdr rand-and-cf))

       ;; Update the x86 state:
       (x86 (!rgfi-size operand-size (reg-index reg rex-byte #.*r*)
                        rand rex-byte x86))
       (x86 (let* ((x86 (!flgi #.*cf* cf x86))
                   (x86 (!flgi #.*pf* 0 x86))
                   (x86 (!flgi #.*af* 0 x86))
                   (x86 (!flgi #.*zf* 0 x86))
                   (x86 (!flgi #.*sf* 0 x86))
                   (x86 (!flgi #.*of* 0 x86)))
              x86))
       (x86 (!rip temp-rip x86)))
      x86))

;; ======================================================================
;; INSTRUCTION: CMPSS/CMPSD
;; ======================================================================

;; Floating-Point Instruction:

(def-inst x86-cmpss/cmpsd-Op/En-RMI

  ;; Shilpi to Cuong: Put as many type decl. as necessary --- look at
  ;; (disassemble$ x86-cmpss/cmpsd-Op/En-RMI) to figure out where you
  ;; need them.

  :parents (two-byte-opcodes fp-opcodes)
  :implemented
  (progn
    (add-to-implemented-opcodes-table 'CMPSD #x0FC2
                                      '(:misc
                                        (eql #.*mandatory-f2h* (prefixes-slice :group-1-prefix prefixes)))
                                      'x86-cmpss/cmpsd-Op/En-RMI)
    (add-to-implemented-opcodes-table 'CMPSS #x0FC2
                                      '(:misc
                                        (eql #.*mandatory-f3h* (prefixes-slice :group-1-prefix prefixes)))
                                      'x86-cmpss/cmpsd-Op/En-RMI))

  :short "Compare scalar single/double precision floating-point values"

  :long
  "<h3>Op/En = RMI: \[OP XMM, XMM/M, IMM\]</h3>
  F3 0F C2: CMPSS xmm1, xmm2/m32, imm8<br/>
  F2 0F C2: CMPSD xmm1, xmm2/m64, imm8<br/>"

  :sp/dp t

  :returns (x86 x86p :hyp (x86p x86))

  :body
  (b* ((ctx 'x86-cmpss/cmpsd-Op/En-RMI)
       (r/m (the (unsigned-byte 3) (mrm-r/m  modr/m)))
       (mod (the (unsigned-byte 2) (mrm-mod  modr/m)))
       (reg (the (unsigned-byte 3) (mrm-reg  modr/m)))
       (lock (eql #.*lock*
                  (prefixes-slice :group-1-prefix prefixes)))
       ((when lock)
        (!!ms-fresh :lock-prefix prefixes))

       ((the (integer 4 8) operand-size)
        (if (equal sp/dp #.*OP-DP*) 8 4))

       (xmm-index ;; Shilpi: Type Decl.?
        (reg-index reg rex-byte #.*r*))
       (xmm
        (xmmi-size operand-size xmm-index x86))

       (p2 (prefixes-slice :group-2-prefix prefixes))

       (p4? (eql #.*addr-size-override*
                 (prefixes-slice :group-4-prefix prefixes)))

       ((mv flg0 xmm/mem (the (integer 0 4) increment-RIP-by) ?v-addr x86)
        (x86-operand-from-modr/m-and-sib-bytes #.*xmm-access* operand-size
                                               p2 p4? temp-rip
                                               rex-byte r/m mod sib 1 x86))

       ((when flg0)
        (!!ms-fresh :x86-operand-from-modr/m-and-sib-bytes flg0))

       ((the (signed-byte #.*max-linear-address-size+1*) temp-rip)
        (+ temp-rip increment-RIP-by))

       ((when (mbe :logic (not (canonical-address-p temp-rip))
                   :exec (<= #.*2^47*
                             (the (signed-byte
                                   #.*max-linear-address-size+1*)
                               temp-rip))))
        (!!ms-fresh :temp-rip-not-canonical temp-rip))

       ((mv flg1 (the (unsigned-byte 8) imm) x86)
        (rm-size 1 (the (signed-byte #.*max-linear-address-size*) temp-rip) :x x86))

       ((when flg1)
        (!!ms-fresh :rm-size-error flg1))

       ((the (signed-byte #.*max-linear-address-size+1*) temp-rip)
        (1+ temp-rip))
       ((when (mbe :logic (not (canonical-address-p temp-rip))
                   :exec (<= #.*2^47*
                             (the (signed-byte
                                   #.*max-linear-address-size+1*)
                               temp-rip))))
        (!!ms-fresh :temp-rip-not-canonical temp-rip))

       ((the (signed-byte #.*max-linear-address-size+1*) addr-diff)
        (-
         (the (signed-byte #.*max-linear-address-size*)
           temp-rip)
         (the (signed-byte #.*max-linear-address-size*)
           start-rip)))
       ((when (< 15 addr-diff))
        (!!ms-fresh :instruction-length addr-diff))

       ((mv flg2 result (the (unsigned-byte 32) mxcsr))
        (if (equal sp/dp #.*OP-DP*)
            (dp-sse-cmp (n02 imm) xmm xmm/mem (mxcsr x86))
          (sp-sse-cmp (n02 imm) xmm xmm/mem (mxcsr x86))))

       ((when flg2)
        (if (equal sp/dp #.*OP-DP*)
            (!!ms-fresh :dp-cmp flg2)
          (!!ms-fresh :sp-cmp flg2)))

       ;; Update the x86 state:
       (x86 (!mxcsr mxcsr x86))

       (x86 (!xmmi-size operand-size xmm-index result x86))

       (x86 (!rip temp-rip x86)))
      x86))

;; ======================================================================

;; To see the rules in the instruction-decoding-and-spec-rules
;; ruleset:

(define show-inst-decoding-and-spec-fn
  ((state))
  :mode :program
  (let ((world (w state)))
    (ruleset-theory 'instruction-decoding-and-spec-rules)))

(defmacro show-inst-decoding-and-spec-ruleset ()
  `(show-inst-decoding-and-spec-fn state))

;; ======================================================================
