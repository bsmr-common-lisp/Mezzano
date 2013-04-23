;;;; setf-full.lisp
;;;; Contains forms that require the parsing code.

(in-package #:sys.int)

(defmacro define-modify-macro (name lambda-list function &optional documentation)
  (multiple-value-bind (required optional rest enable-keys keys allow-other-keys aux)
      (parse-ordinary-lambda-list lambda-list)
    (when (or enable-keys keys allow-other-keys aux)
      (error "&KEYS and &AUX not permitted in define-modify-macro lambda list"))
    (let ((reference (gensym)) (env (gensym)))
      `(defmacro ,name (&environment ,env ,reference ,@lambda-list)
	 ,documentation
	 (multiple-value-bind (dummies vals newvals setter getter)
	     (get-setf-expansion ,reference ,env)
	   (when (cdr newvals)
	     (error "Can't expand this"))
	   `(let* (,@(mapcar #'list dummies vals) (,(car newvals)
						   ,(list* ',function getter
                                                           ,@required
                                                           ,@(mapcar #'car optional)
                                                           ,@(when rest (list rest)))))
	      ,setter))))))

(defmacro define-setf-expander (access-fn lambda-list &body body)
  (let ((whole (gensym "WHOLE"))
	(env (gensym "ENV")))
    (multiple-value-bind (new-lambda-list env-binding)
	(fix-lambda-list-environment lambda-list)
      `(eval-when (:compile-toplevel :load-toplevel :execute)
         (%define-setf-expander ',access-fn
                                (lambda (,whole ,env)
                                  (declare (lambda-name (setf-expander ,access-fn))
                                           (ignorable ,whole ,env))
                                  ,(expand-destructuring-lambda-list new-lambda-list access-fn body
                                                                     whole `(cdr ,whole)
                                                                     (when env-binding
                                                                       (list `(,env-binding ,env))))))
	 ',access-fn))))

(eval-when (:compile-toplevel :load-toplevel :execute)
(defun %define-setf-expander (access-fn expander)
  (setf (get access-fn 'setf-expander) expander))
)

(define-modify-macro incf (&optional (delta 1)) +)
(define-modify-macro decf (&optional (delta 1)) -)

(defun %putf (plist indicator value)
  (do ((i plist (cddr i)))
      ((null i)
       (list* indicator value plist))
    (when (eql (car i) indicator)
      (setf (cadr i) value)
      (return plist))))

(define-setf-expander getf (place indicator &optional default &environment env)
  (multiple-value-bind (temps vals stores
                              store-form access-form)
      (get-setf-expansion place env);Get setf expansion for place.
    (let ((indicator-temp (gensym))
          (store (gensym))     ;Temp var for byte to store.
          (stemp (first stores))) ;Temp var for int to store.
      (when (cdr stores) (error "Can't expand this."))
      ;; Return the setf expansion for LDB as five values.
      (values (list* indicator-temp temps)       ;Temporary variables.
              (list* indicator vals)     ;Value forms.
              (list store)             ;Store variables.
              `(let ((,stemp (%putf ,access-form ,indicator-temp ,store)))
                 ,default
                 ,store-form
                 ,store)               ;Storing form.
              `(getf ,access-form ,indicator-temp ,default))))) ;Accessing form.

;; FIXME...
(defmacro psetf (&rest pairs)
  (when pairs
    (when (null (cdr pairs))
      (error "Odd number of arguments to PSETF"))
    (let ((value (gensym)))
      `(let ((,value ,(cadr pairs)))
	 (psetf ,@(cddr pairs))
	 (setf ,(car pairs) ,value)
	 nil))))

;; FIXME...
(defmacro rotatef (&rest places)
  (when places
    (let ((results '()))
      (dolist (x places)
        (push x results)
        (push x results))
      (push (first places) results)
      (setf results (nreverse results))
      (setf (first results) 'psetf)
      `(progn ,results 'nil))))