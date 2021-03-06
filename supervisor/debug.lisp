;;;; Copyright (c) 2011-2015 Henry Harrington <henry.harrington@gmail.com>
;;;; This code is licensed under the MIT license.

;;; Low-level debugging output for the supervisor.

(in-package :mezzano.supervisor)

;; The debug stream functions use line-buffered output, but output can
;; be forced using the DEBUG-FORCE-OUTPUT function.

;; The debug pesudostream must be a function that takes one or two arguments.
;; The first argument is a keyword specifying the operation,
;; the second argument is the data for the operation.
;; Operations:
;;     :read-char     Read a character from the stream.
;;     :clear-input   Clear any available input.
;;     :write-char    Write a character to the stream.
;;     :write-string  Write a string to the stream.
;;     :force-output  Same as CL:FORCE-OUTPUT.
(defvar *debug-pesudostream*)

(defun debug-set-output-pesudostream (pesudostream)
  (setf *debug-pesudostream* pesudostream))

(defun debug-read-char ()
  (when (boundp '*debug-pesudostream*)
    (funcall *debug-pesudostream* :read-char)))

(defun debug-clear-input ()
  (when (boundp '*debug-pesudostream*)
    (funcall *debug-pesudostream* :clear-input)))

(defun debug-write-string (string)
  (when (boundp '*debug-pesudostream*)
    (funcall *debug-pesudostream* :write-string string)))

(defun debug-write-char (char)
  (when (boundp '*debug-pesudostream*)
    (funcall *debug-pesudostream* :write-char char)))

(defun debug-write-line (string)
  (when (boundp '*debug-pesudostream*)
    (funcall *debug-pesudostream* :write-string string)
    (funcall *debug-pesudostream* :write-char #\Newline)
    (funcall *debug-pesudostream* :force-output)))

;;; Print a negative fixnum. Use negative numbers to avoid problems
;;; near most-negative-fixnum.
(defun debug-write-fixnum-1 (fixnum base)
  (unless (zerop fixnum)
    (multiple-value-bind (quot rem)
        (truncate fixnum base)
      (debug-write-fixnum-1 quot base)
      (debug-write-char (char "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" (- rem))))))

(defun debug-write-fixnum (fixnum &optional (base 16))
  (cond ((plusp fixnum)
         (debug-write-fixnum-1 (- fixnum) base))
        ((minusp fixnum)
         (debug-write-char #\-)
         (debug-write-fixnum-1 fixnum base))
        (t (debug-write-char #\0))))

(defun debug-print-line-1 (things)
  (dolist (thing things)
    (cond ((sys.int::character-array-p thing)
           (debug-write-string thing))
          ((symbolp thing)
           (debug-write-string (symbol-name thing)))
          ((sys.int::fixnump thing)
           (debug-write-fixnum thing))
          (t (debug-write-string "#<")
             (debug-write-fixnum (sys.int::lisp-object-address thing))
             (debug-write-string ">"))))
  (when (boundp '*debug-pesudostream*)
    (funcall *debug-pesudostream* :write-char #\Newline)
    (funcall *debug-pesudostream* :force-output)))

(defun debug-print-line (&rest things)
  (declare (dynamic-extent things))
  (debug-print-line-1 things))

(defun debug-start-line-p ()
  (when (boundp '*debug-pesudostream*)
    (funcall *debug-pesudostream* :start-line-p)))

(defun debug-force-output ()
  (when (boundp '*debug-pesudostream*)
    (funcall *debug-pesudostream* :force-output)))

(defvar *panic-in-progress* nil)

(defun panic (&rest things)
  (declare (dynamic-extent things))
  (when (and (boundp '*panic-in-progress*)
             *panic-in-progress*)
    (sys.int::%cli)
    (loop (sys.int::%hlt)))
  ;; Stop the world, just in case printing the backtrace requires paging stuff in.
  (setf *world-stopper* (current-thread)
        *panic-in-progress* t)
  (set-panic-light)
  (sys.int::%sti)
  (debug-print-line-1 things)
  (do ((i 0 (1+ i))
       (fp (sys.int::read-frame-pointer)
           (sys.int::memref-unsigned-byte-64 fp 0)))
      ((eql fp 0))
    (debug-print-line fp " " (sys.int::memref-unsigned-byte-64 fp 1)))
  (loop (sys.int::%hlt)))

(defmacro ensure (condition &rest things)
  `(when (not ,condition)
     (panic ,@things)))
