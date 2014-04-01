(import (scheme base)
	(scheme cxr)
	(picrin macro)
	(scheme write))

  ;;; utility functions
(define (reverse* l)
  ;; (reverse* '(a b c d . e)) => (e d c b a)
  (let loop ((a '())
	     (d l))
    (if (pair? d)
	(loop (cons (car d) a) (cdr d))
	(cons d a))))

(define (number->string n)
  ;; fixme
  (case n
    ((0) "0")
    ((1) "1")
    ((2) "2")
    ((3) "3")
    (else "hogee")))

(define (var->sym v)
  (let loop ((cnt 0)
	     (v v))
    (if (symbol? v)
	(string->symbol (string-append (symbol->string v) "/" (number->string cnt)))
	(loop (+ 1 cnt) (car v)))))

(define push-var list)

(define (every? pred l)
  (if (null? l)
      #t
      (and (pred (car l)) (every? pred (cdr l)))))

(define (flatten l)
  (cond
   ((null? l) '())
   ((pair? (car l))
    (append (flatten (car l)) (flatten (cdr l))))
   (else
    (cons (car l) (flatten (cdr l))))))

;;; main function
(define-syntax syntax-rules
  (er-macro-transformer
   (lambda (form r compare)
     (define _define (r 'define))
     (define _let (r 'let))
     (define _if (r 'if))
     (define _begin (r 'begin))
     (define _lambda (r 'lambda))
     (define _set! (r 'set!))
     (define _not (r 'not))
     (define _and (r 'and))
     (define _car (r 'car))
     (define _cdr (r 'cdr))
     (define _cons (r 'cons))
     (define _pair? (r 'pair?))
     (define _null? (r 'null?))
     (define _symbol? (r 'symbol?))
     (define _eqv? (r 'eqv?))
     (define _map (r 'map))
     (define _vector->list (r 'vector->list))
     (define _list->vector (r 'list->vector))
     (define _quote (r 'quote))
     (define _quasiquote (r 'quasiquote))
     (define _unquote (r 'unquote))
     (define _unquote-splicing (r 'unquote-splicing))
     (define _syntax-error (r 'syntax-error))
     (define _call/cc (r 'call/cc))
     (define _er-macro-transformer (r 'er-macro-transformer))

     (define (compile-match ellipsis literals pattern)
       (letrec ((compile-match-base
		 (lambda (pattern)
		   (cond ((compare pattern (r '_)) (values #f '()))
			 ((member pattern literals)
			  (values
			   `(,_if (,_and (,_symbol? expr) (cmp expr (rename ',pattern)))
				  #f
				  (exit #f))
			   '()))
			 ((eq? pattern ellipsis)
			  (values `(,_syntax-error "invalid pattern") '()))
			 ((symbol? pattern)
			  (values `(,_set! ,(var->sym pattern) expr) (list pattern)))
			 ((pair? pattern)
			  (compile-match-list pattern))
			 ((vector? pattern)
			  (compile-match-vector pattern))
			 (else
			  (values
			   `(,_if (,_not (,_eqv? ',pattern expr))
				  (exit #f))
			   '())))))

		(compile-match-list
		 (lambda (pattern)
		   (let loop ((pattern pattern)
			      (matches '())
			      (vars '())
			      (accessor 'expr))
		     (cond ;; (hoge)
		      ((not (pair? (cdr pattern)))
		       (let*-values (((match1 vars1) (compile-match-base (car pattern)))
				     ((match2 vars2) (compile-match-base (cdr pattern))))
			 (values
			  `(,_begin ,@(reverse matches)
				    (,_if (,_pair? ,accessor)
					  (,_begin
					   (,_let ((expr (,_car ,accessor)))
						  ,match1)
					   (,_let ((expr (,_cdr ,accessor)))
						  ,match2))
					  (exit #f)))
			  (append vars (append vars1 vars2)))))
		      ;; (hoge ... rest args)
		      ((eq? (cadr pattern) ellipsis)
		       (let-values (((match-r vars-r) (compile-match-list-reverse pattern)))
			 (values
			  `(,_begin ,@(reverse matches)
				    (,_let ((expr (,_let loop ((a ())
							       (d ,accessor))
							 (,_if (,_pair? d)
							       (loop (,_cons (,_car d) a) (,_cdr d))
							       (,_cons d a)))))
					   ,match-r))
			  (append vars vars-r))))
		      (else
		       (let-values (((match1 vars1) (compile-match-base (car pattern))))
			 (loop (cdr pattern)
			       (cons `(,_if (,_pair? ,accessor)
					    (,_let ((expr (,_car,accessor)))
						   ,match1)
					    (exit #f))
				     matches)
			       (append vars vars1)
			       `(,_cdr ,accessor))))))))

		(compile-match-list-reverse
		 (lambda (pattern)
		   (let loop ((pattern (reverse* pattern))
			      (matches '())
			      (vars '())
			      (accessor 'expr))
		     (cond ((eq? (car pattern) ellipsis)
			    (let-values (((match1 vars1) (compile-match-ellipsis (cadr pattern))))
			      (values
			       `(,_begin ,@(reverse matches)
					 (,_let ((expr ,accessor))
						,match1))
			       (append vars vars1))))
			   (else
			    (let-values (((match1 vars1) (compile-match-base (car pattern))))
			      (loop (cdr pattern)
				    (cons `(,_let ((expr (,_car ,accessor))) ,match1) matches)
				    (append vars vars1)
				    `(,_cdr ,accessor))))))))

		(compile-match-ellipsis
		 (lambda (pattern)
		   (let-values (((match vars) (compile-match-base pattern)))
		     (values
		      `(,_let loop ((expr expr))
			      (,_if (,_not (,_null? expr))
				    (,_let ,(map (lambda (var) `(,(var->sym var) '())) vars)
					   (,_let ((expr (,_car expr)))
						  ,match)
					   ,@(map
					      (lambda (var)
						`(,_set! ,(var->sym (push-var var))
							 (,_cons ,(var->sym var) ,(var->sym (push-var var)))))
					      vars)
					   (loop (,_cdr expr)))))
		      (map push-var vars)))))

		(compile-match-vector
		 (lambda (pattern)
		   (let-values (((match vars) (compile-match-list (vector->list pattern))))
		     (values
		      `(,_let ((expr (,_vector->list expr)))
			      ,match)
		      vars)))))

	 (let-values (((match vars) (compile-match-base (cdr pattern))))
	   (values `(,_let ((expr (,_cdr expr)))
			   ,match
			   #t)
		   vars))))

       ;;; compile expand
     (define (compile-expand ellipsis reserved template)
       (letrec ((compile-expand-base
		 (lambda (template ellipsis-valid)
		   (cond ((member template reserved)
			  (values (var->sym template) (list template)))
			 ((symbol? template)
			  (values `(rename ',template) '()))
			 ((pair? template)
			  (compile-expand-list template ellipsis-valid))
			 ((vector? template)
			  (compile-expand-vector template ellipsis-valid))
			 (else
			  (values `',template '())))))

		(compile-expand-list
		 (lambda (template ellipsis-valid)
		   (let loop ((template template)
			      (expands '())
			      (vars '()))
		     (cond ;; (... hoge)
		      ((and ellipsis-valid
			    (pair? template)
			    (eq? (car template) ellipsis))
		       (if (and (pair? (cdr template)) (null? (cddr template)))
			   (compile-expand-base (cadr template) #f)
			   (values '(,_syntax-error "invalid template") '())))
		      ;; hoge
		      ((not (pair? template))
		       (let-values (((expand1 vars1)
				     (compile-expand-base template ellipsis-valid)))
			 (values
			  `(,_quasiquote (,@(reverse expands) . (,_unquote ,expand1)))
			  (append vars vars1))))
		      ;; (hoge . poyo)
		      ((not (pair? (cdr template)))
		       (let*-values (((expand1 vars1)
				      (compile-expand-base (car template) ellipsis-valid))
				     ((expand2 vars2)
				      (compile-expand-base (cdr template) ellipsis-valid)))
			 (values
			  `(,_quasiquote (,@(reverse expands) (,_unquote ,expand1) . (,_unquote ,expand2)))
			  (append (append vars vars1) vars2))))
		      ;; (a ... rest syms)
		      ((and ellipsis-valid
			    (eq? (cadr template) ellipsis))
		       (let-values (((expand1 vars1)
				     (compile-expand-base (car template) ellipsis-valid)))
			 (loop (cddr template)
			       (cons
				`(,_unquote-splicing
				  (,_map (,_lambda ,(map var->sym vars1) ,expand1)
					 ,@(map (lambda (v) (var->sym (push-var v))) vars1)))
				expands)
			       (append vars (map push-var vars1)))))
		      (else
		       (let-values (((expand1 vars1)
				     (compile-expand-base (car template) ellipsis-valid)))
			 (loop (cdr template)
			       (cons
				`(,_unquote ,expand1)
				expands)
			       (append vars vars1))))))))

		(compile-expand-vector
		 (lambda (template ellipsis-valid)
		   (let-values (((expand1 vars1)
				 (compile-expand-list (vector->list template) ellipsis-valid)))
		     `(,_list->vector ,expand1)
		     vars1))))

	 (compile-expand-base template #t)))

     (define (check-vars vars-pattern vars-template)
       ;;fixme
       #t)

     (define (compile-rule ellipsis literals rule)
       (let ((pattern (car rule))
	     (template (cadr rule)))
	 (let*-values (((match vars-match)
			(compile-match ellipsis literals pattern))
		       ((expand vars-expand)
			(compile-expand ellipsis (flatten vars-match) template)))
	   (if (check-vars vars-match vars-expand)
	       (list vars-match match expand)
	       'mismatch))))

     (define (expand-clauses clauses rename)
       (cond ((null? clauses)
	      `(,_quote (syntax-error "no matching pattern")))
	     ((eq? (car clauses) 'mismatch)
	      `(,_syntax-error "invalid rule"))
	     (else
	      (let ((vars (car (car clauses)))
		    (match (cadr (car clauses)))
		    (expand (caddr (car clauses))))
		`(,_let ,(map (lambda (v) (list (var->sym v) '())) vars)
			(,_let ((result (,_call/cc (,_lambda (exit) ,match))))
			       (,_if result
				     ,expand
				     ,(expand-clauses (cdr clauses) rename))))))))

     (define (normalize-form form)
       (if (and (list? form) (>= (length form) 2))
	   (let ((ellipsis '...)
		 (literals (cadr form))
		 (rules (cddr form)))

	     (when (symbol? literals)
		   (set! ellipsis literals)
		   (set! literals (car rules))
		   (set! rules (cdr rules)))

	     (if (and (symbol? ellipsis)
		      (list? literals)
		      (every? symbol? literals)
		      (list? rules)
		      (every? (lambda (l) (and (list? l) (= (length l) 2))) rules))
		 `(syntax-rules ,ellipsis ,literals ,@rules)
		 #f))
	   #f))

     (let ((form (normalize-form form)))
       (if form
	   (let ((ellipsis (cadr form))
		 (literals (caddr form))
		 (rules (cdddr form)))
	     (let ((clauses (map (lambda (rule) (compile-rule ellipsis literals rule))
				 rules)))
	       `(,_er-macro-transformer
		 (,_lambda (expr rename cmp)
			   ,(expand-clauses clauses r)))))

	   `(,_syntax-error "malformed syntax-rules"))))))

;;; test code
(import (scheme write))

(define-syntax hoge
  (syntax-rules ()
    ((hoge (a ...) ...) '((a ...) ...))
    ((hoge (a b) ...) '(a ...))
    ((hoge a b ... c . d) 'c)))

(display (hoge (1 2 3) (3 4 5) (5 6 7)))
(newline)
(display (hoge (a b) (c d) (e f)))
(newline)
(display (hoge a b c))
(newline)
