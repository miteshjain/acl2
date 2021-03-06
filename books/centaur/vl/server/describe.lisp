; VL Verilog Toolkit
; Copyright (C) 2008-2014 Centaur Technology
;
; Contact:
;   Centaur Technology Formal Verification Group
;   7600-C N. Capital of Texas Highway, Suite 300, Austin, TX 78731, USA.
;   http://www.centtech.com/
;
; License: (An MIT/X11-style license)
;
;   Permission is hereby granted, free of charge, to any person obtaining a
;   copy of this software and associated documentation files (the "Software"),
;   to deal in the Software without restriction, including without limitation
;   the rights to use, copy, modify, merge, publish, distribute, sublicense,
;   and/or sell copies of the Software, and to permit persons to whom the
;   Software is furnished to do so, subject to the following conditions:
;
;   The above copyright notice and this permission notice shall be included in
;   all copies or substantial portions of the Software.
;
;   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;   DEALINGS IN THE SOFTWARE.
;
; Original author: Jared Davis <jared@centtech.com>

(in-package "VL")
(include-book "../mlib/writer")
(include-book "../mlib/allexprs")
(include-book "../mlib/find")
(include-book "../mlib/modnamespace")
(include-book "../mlib/fmt")
(local (include-book "../util/arithmetic"))

(defxdoc vl-describe
  :parents (server)
  :short "@(call vl-describe) describes the uses of @('name') in the module
@('x')."

  :long "<p>This is a useful way to interactively inspect modules.  The
@('name') is typically some kind of name that is used within the module @('x'),
and might be the name of a wire, port, parameter, submodule instance, or what
have you.</p>

<p>@('vl-describe') looks through the module for uses of this name and returns
a human-readable string that describes what it has found.  This report is meant
to describe all of the places that @('name') is used.</p>")

(define vl-modinsts-that-mention ((name stringp)
                                  (x    vl-modinstlist-p))
  :returns (sub-x vl-modinstlist-p)
  (b* (((when (atom x))
        nil)
       (exprs (vl-modinst-allexprs (car x)))
       (names (vl-exprlist-varnames exprs))
       ((when (member-equal name names))
        (cons (vl-modinst-fix (car x))
              (vl-modinsts-that-mention name (cdr x)))))
    (vl-modinsts-that-mention name (cdr x))))

(define vl-assigns-that-mention ((name stringp)
                                 (x    vl-assignlist-p))
  :returns (sub-x vl-assignlist-p)
  (b* (((when (atom x))
        nil)
       (exprs (vl-assign-allexprs (car x)))
       (names (vl-exprlist-varnames exprs))
       ((when (member-equal name names))
        (cons (vl-assign-fix (car x))
              (vl-assigns-that-mention name (cdr x)))))
    (vl-assigns-that-mention name (cdr x))))

(define vl-describe-pp-plainarg ((name stringp)
                                 (x    vl-plainarg-p)
                                 (n    natp           "Position in the argument list.")
                                 &key (ps 'ps))
  (b* (((vl-plainarg x) x)
       ((unless x.expr)
        ps)
       (names (vl-expr-varnames x.expr))
       ((unless (member-equal name names))
        ps)
       (directp (and (vl-idexpr-p x.expr)
                     (equal (vl-idexpr->name x.expr) name)))
       (htmlp  (vl-ps->htmlp)))
    (vl-ps-seq (if htmlp
                   (vl-print-markup "<dd>")
                 (vl-print " - "))
               (vl-print (if directp
                             "Directly connected to"
                           "Connected to"))
               (if (not x.dir)
                   ps
                 (vl-ps-seq
                  (vl-print " ")
                  (vl-print (vl-direction-string x.dir))))
               (vl-print " port ")
               (if x.portname
                   (vl-ps-span "vl_id" (vl-print x.portname))
                 (vl-ps-seq (vl-print "#")
                            (vl-print n)))
               (vl-println "")
               (if directp
                   ps
                 (vl-ps-seq (vl-when-html (vl-print-markup "<small>"))
                            (vl-print "Expression: ")
                            (vl-ps-span "desc_detail"
                                        (vl-pp-origexpr x.expr))
                            (vl-println-markup "</small>")))
               (if htmlp
                   (vl-println-markup "</dd>")
                 (vl-println "")))))

(define vl-describe-pp-plainarglist ((name stringp)
                                     (x    vl-plainarglist-p)
                                     (n    natp)
                                     &key (ps 'ps))
  (if (atom x)
      ps
    (vl-ps-seq (vl-describe-pp-plainarg name (car x) n)
               (vl-describe-pp-plainarglist name (cdr x) (+ 1 n)))))

(define vl-describe-pp-namedarg ((name stringp)
                                 (x    vl-namedarg-p)
                                 &key (ps 'ps))
  (b* (((vl-namedarg x) x)
       ((unless x.expr)
        ps)
       (names (vl-expr-varnames x.expr))
       ((unless (member-equal name names))
        ps)
       (directp (and (vl-idexpr-p x.expr)
                     (equal (vl-idexpr->name x.expr) name)))
       (htmlp  (vl-ps->htmlp)))
    (vl-ps-seq (if htmlp
                   (vl-print-markup "<dd>")
                 (vl-print " - "))
               (vl-print (if directp
                             "Directly connected to port "
                           "Connected to port "))
               (vl-ps-span "vl_id" (vl-print x.name))
               (vl-println "")
               (if directp
                   ps
                 (vl-ps-seq (vl-when-html (vl-print-markup "<small>"))
                            (vl-print "Expression: ")
                            (vl-ps-span "desc_detail"
                                        (vl-pp-origexpr x.expr))
                            (vl-println-markup "</small>")))
               (if htmlp
                   (vl-println-markup "</small></dd>")
                 (vl-println "")))))

(define vl-describe-pp-namedarglist ((name stringp)
                                     (x    vl-namedarglist-p)
                                     &key (ps 'ps))
  (if (atom x)
      ps
    (vl-ps-seq (vl-describe-pp-namedarg name (car x))
               (vl-describe-pp-namedarglist name (cdr x)))))

(define vl-describe-pp-modinst ((name stringp)
                                (x    vl-modinst-p)
                                &key (ps 'ps))
  ;; We assume that X does in fact mention name somewhere.
  ;; BOZO deal with paramargs and range and gatedelay nonsense
  (b* (((vl-modinst x) x)

       (htmlp (vl-ps->htmlp))
       (id (str::cat (str::natstr (vl-location->line x.loc)) "-"
                     (str::natstr (vl-location->col x.loc)))))
      (vl-ps-seq
       (vl-when-html (vl-print-markup "<dl class=\"desc_modinsts\"><dt>"))
       (vl-print " In ")
       (if (not x.instname)
           ps
         (vl-ps-seq
          (vl-ps-span "vl_id" (vl-print x.instname))
          (vl-print ", an ")))
       (vl-print "instance of ")
       (vl-print-modname x.modname)
       (vl-when-html (vl-print-markup "<br/><small>"))
       (vl-print-loc x.loc)
       (vl-when-html (vl-print-markup "</small>"))

       (if htmlp
           (vl-print-markup "</dt>")
         (vl-println ""))
       (vl-arguments-case x.portargs
         :vl-arguments-named (vl-describe-pp-namedarglist name x.portargs.args)
         :vl-arguments-plain (vl-describe-pp-plainarglist name x.portargs.args 1))

       (vl-when-html
        (let* ((detail (with-local-ps
                         (vl-ps-update-htmlp htmlp)
                         ;; BOZO a proper scopestack here would be nice
                         (vl-pp-modinst x nil)))
               (hidep  (> (length detail) 2500))
               (style  (if hidep " style=\"display:none\"" "")))
          (vl-ps-seq
           (if (not hidep)
               ps
             (vl-ps-seq
              (vl-print-markup "<dd><a href=\"javascript:void(0)\" onClick=\"replaceDots('")
              (vl-print-markup id)
              (vl-print-markup "')\" id=\"")
              (vl-print-markup id)
              (vl-print-markup "_link\">...</a></dd>")))

           (vl-ps-seq
            (vl-print-markup "<dd id=\"")
            (vl-print-markup id)
            (vl-print-markup "\"")
            (vl-print-markup style)
            (vl-print-markup ">")
;            (vl-print-markup "<p>Detail length: ")
;            (vl-print (length detail))
;            (vl-print-markup "</p>")
            (vl-println-markup "<div class=\"vl_src\">")
            (vl-println-markup detail) ;; since it already got formatted
            (vl-println-markup "</div></dd>")))))

       (if htmlp
           (vl-println-markup "</dl>")
         (vl-println "")))))

(define vl-describe-pp-modinstlist-aux (name x &key (ps 'ps))
  :guard (and (stringp name)
              (vl-modinstlist-p x))
  (if (atom x)
      ps
    (vl-ps-seq (vl-describe-pp-modinst name (car x))
               (vl-describe-pp-modinstlist-aux name (cdr x)))))

(define vl-describe-pp-modinsts (name x &key (ps 'ps))
  :guard (and (stringp name)
              (vl-modinstlist-p x))
  (let ((relevant (vl-modinsts-that-mention name x))
        (htmlp    (vl-ps->htmlp)))
    (if (not relevant)
        ps
      (vl-ps-seq (vl-when-html (vl-print-markup "<h4>"))
                 (vl-print "Used in ")
                 (vl-print (len relevant))
                 (vl-print " module instance")
                 (vl-print (if (consp (cdr relevant)) "s" ""))
                 (if htmlp
                     (vl-println-markup "</h4>")
                   (vl-ps-seq (vl-println "")
                              (vl-println "")))
                 (vl-describe-pp-modinstlist-aux name relevant)))))

(define vl-describe-pp-assign ((name stringp)
                               (x    vl-assign-p)
                               &key (ps 'ps))
  ;; We assume that name is mentioned somewhere in X.
  (b* (((vl-assign x) x)
       (lhs-names (vl-expr-varnames x.lvalue))
       (rhs-names (vl-expr-varnames x.expr))
       (writtenp  (member-equal name lhs-names))
       (readp     (member-equal name rhs-names))
       (htmlp     (vl-ps->htmlp)))
    (vl-ps-seq
     (vl-when-html (vl-println-markup "<dl class=\"desc_assigns\">")
                   (vl-print-markup "<dt>"))
     (cond ((and readp writtenp)
            (vl-print "Read and written "))
           (readp
            (vl-print "Read "))
           (writtenp
            (vl-print "Written "))
           (t
            (vl-print "Er, wtf... not actually used?? ")))
     (vl-print "at ")
     (vl-print-loc x.loc)
     (if htmlp
         (vl-println-markup "</dt>")
       (vl-println ""))
     (vl-when-html (vl-println-markup "<dd class=\"vl_src\"><small>"))
     (vl-pp-assign x)
     (if htmlp
         (vl-println-markup "</small></dd></dt></dl>")
       (vl-println "")))))

(define vl-describe-pp-assignlist-aux ((name stringp)
                                       (x    vl-assignlist-p)
                                       &key (ps 'ps))
  (if (atom x)
      ps
    (vl-ps-seq (vl-describe-pp-assign name (car x))
               (vl-describe-pp-assignlist-aux name (cdr x)))))

(define vl-describe-pp-assignlist ((name stringp)
                                   (x    vl-assignlist-p)
                                   &key (ps 'ps))
  (b* ((relevant (vl-assigns-that-mention name x))
       (htmlp    (vl-ps->htmlp))
       ((unless relevant)
        ps))
    (vl-ps-seq (vl-when-html (vl-print-markup "<h4>"))
               (vl-print "Used in ")
               (vl-print (len relevant))
               (vl-print " assignment")
               (vl-print (if (consp (cdr relevant)) "s" ""))
               (if htmlp
                   (vl-println-markup "</h4>")
                 (vl-ps-seq (vl-println "")
                            (vl-println "")))
               (vl-describe-pp-assignlist-aux name relevant))))

(define vl-pp-moduleitem (x &key (ps 'ps))
  :guard (or (vl-vardecl-p x)
             (vl-paramdecl-p x)
             (vl-modinst-p x)
             (vl-gateinst-p x)
             (vl-fundecl-p x)
             (vl-taskdecl-p x))
  (case (tag x)
    (:vl-vardecl (vl-pp-vardecl x))
    (:vl-paramdecl (vl-println "// BOZO implement paramdecl printing"))
    (:vl-modinst
     (vl-ps-seq (vl-when-html (vl-print-markup "<small>")
                              (vl-print-loc (vl-modinst->loc x))
                              (vl-println-markup "</small>"))
                ;; BOZO proper scopestack would be nice
                (vl-pp-modinst x nil)))
    (:vl-gateinst
     (vl-ps-seq (vl-when-html (vl-print-markup "<small>")
                              (vl-print-loc (vl-gateinst->loc x))
                              (vl-println-markup "</small>"))
                (vl-pp-gateinst x)))
    (:vl-fundecl
     (vl-ps-seq (vl-when-html (vl-print-markup "<small>")
                              (vl-print-loc (vl-fundecl->loc x))
                              (vl-println-markup "</small>"))
                (vl-pp-fundecl x)))
    (:vl-taskdecl
     (vl-ps-seq (vl-when-html (vl-print-markup "<small>")
                              (vl-print-loc (vl-taskdecl->loc x))
                              (vl-println-markup "</small>"))
                (vl-pp-taskdecl x)))
    (otherwise (progn$ (impossible)
                       ps))))



(define vl-gateinsts-that-mention ((name stringp)
                                   (x    vl-gateinstlist-p))
  :returns (sub-x vl-gateinstlist-p)
  (b* (((when (atom x))
        nil)
       (exprs (vl-gateinst-allexprs (car x)))
       (names (vl-exprlist-varnames exprs))
       ((when (member-equal name names))
        (cons (vl-gateinst-fix (car x))
              (vl-gateinsts-that-mention name (cdr x)))))
    (vl-gateinsts-that-mention name (cdr x))))

(define vl-describe-pp-gateinstlist-aux ((x vl-gateinstlist-p)
                                         &key (ps 'ps))
  (if (atom x)
      ps
    (vl-ps-seq (vl-when-html (vl-println-markup "<div class=\"vl_src\">"))
               (vl-pp-gateinst (car x))
               (vl-when-html (vl-println-markup "</div>")))))

(define vl-describe-pp-gateinsts ((name stringp)
                                  (x    vl-gateinstlist-p)
                                  &key (ps 'ps))
  (b* ((relevant (vl-gateinsts-that-mention name x))
       (htmlp    (vl-ps->htmlp))
       ((unless relevant)
        ps))
    (vl-ps-seq (vl-when-html (vl-print-markup "<h4>"))
               (vl-print "Used in ")
               (vl-print (len relevant))
               (vl-print " gate instance")
               (vl-print (if (vl-plural-p relevant) "s" ""))
               (if htmlp
                   (vl-println-markup "</h4>")
                 (vl-ps-seq (vl-println "")
                            (vl-println "")))
               (vl-describe-pp-gateinstlist-aux relevant))))

(define vl-pp-describe ((name stringp)
                        (x    vl-module-p)
                        &key (ps 'ps))
  :guard-debug t
  (b* (((vl-module x) x)

       (some-uses-will-not-be-displayed-p
        (b* ((x-prime (change-vl-module x
                                        :modinsts nil
                                        :assigns nil
                                        ;; BOZO we don't actually print the
                                        ;; ports that the wire appears in, but
                                        ;; that should be fine in practice.
                                        :ports nil
                                        :portdecls nil
                                        :gateinsts nil))
             (others  (vl-exprlist-varnames (vl-module-allexprs x-prime))))
          (member-equal name others)))

       (htmlp (vl-ps->htmlp))

       (ps (if some-uses-will-not-be-displayed-p
               (vl-ps-seq
                (vl-when-html (vl-print-markup "<h4>"))
                (vl-print "Warning: some uses are not displayed!")
                (vl-when-html (vl-print-markup "</h4>"))
                (if (not htmlp)
                    (vl-ps-seq (vl-println "")
                               (vl-println ""))
                  ps))
             ps))

       (ss (make-vl-scopestack-null) ;; bozo stupid hack
           )
       (ss (vl-scopestack-push x ss))

       (portdecl (vl-find-portdecl name x.portdecls))
       (item     (vl-scopestack-find-item name ss))

       (ps       (if item
                     (vl-ps-seq
                      (vl-when-html (vl-print-markup "<h4>"))
                      (vl-basic-cw "Module item for ~s0" name)
                      (vl-when-html (vl-println-markup "</h4>"))
                      (vl-when-html (vl-println-markup "<div class=\"vl_src\">"))
                      (if (and portdecl (not (equal item portdecl)))
                          (vl-ps-seq (vl-cw "~a0" portdecl)
                                     (vl-cw "~a0" item))
                        ps)
                      (if item
                          (vl-cw "~a0" item)
                        ps)
                      (vl-when-html (vl-println-markup "</div>")))
                   (vl-ps-seq
                    (vl-when-html (vl-print-markup "<h4>"))
                    (vl-basic-cw "No module item found for ~s0" name)
                    (vl-when-html (vl-println-markup "</h4>")))))

       (ps (if htmlp
               ps
             (vl-ps-seq (vl-println "")
                        (vl-println ""))))

       (ps    (vl-describe-pp-assignlist name x.assigns))
       (ps    (vl-describe-pp-modinsts name x.modinsts))
       (ps    (vl-describe-pp-gateinsts name x.gateinsts)))

      ps))

(define vl-describe ((name stringp)
                     (x    vl-module-p))
  (with-local-ps (vl-pp-describe name x)))
