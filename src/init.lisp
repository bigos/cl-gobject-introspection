(in-package :gir)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (cffi:define-foreign-library gobject
      (:darwin "libgobject-2.0.dylib")
    (:unix (:or "libgobject-2.0.so.0" "libgobject-2.0.so"))
    (:windows "libgobject-2.0-0.dll")
    (t "libgobject-2.0"))
  (cffi:define-foreign-library girepository
      (:darwin "libgirepository-1.0.dylib")
    (:unix (:or "libgirepository-1.0.so" "libgirepository-1.0.so.1"))
    (:windows (:or "libgirepository-1.0.dll" "libgirepository-1.0.0.dll"
                   "libgirepository-1.0-1.dll"))
    (t "libgirepository-1.0")))

(cffi:use-foreign-library gobject)
(cffi:use-foreign-library girepository)

(cffi:defcfun (%g-type-init "g_type_init") :void)

(%g-type-init)

;;
;; memory management
;;

(cffi:defcfun g-malloc :pointer
  (size :uint))

(cffi:defcfun g-free :void
  (ptr :pointer))

;;
;; char** foreign type
;;

(cffi:define-foreign-type strv-ffi ()
  ()
  (:actual-type :pointer))

(cffi:define-parse-method strv-ffi (&key)
  (make-instance 'strv-ffi))

(defmethod cffi:translate-to-foreign (data (type strv-ffi))
  (error "Not supported"))
(defmethod cffi:translate-from-foreign (pointer (type strv-ffi))
  (prog1
      (iter (for i from 0)
	    (for ptr = (cffi:mem-aref pointer :pointer i))
	    (until (cffi:null-pointer-p ptr))
	    (collect (cffi:foreign-string-to-lisp ptr))
	    (g-free ptr))
    (g-free pointer)))

;;
;; GSList of string
;;

(cffi:defcstruct g-slist
    (data :pointer)
  (next :pointer))
(cffi:defctype g-slist (:struct g-slist))

(cffi:defcfun g-slist-alloc (:pointer g-slist))

(cffi:defcfun g-slist-free :void (list (:pointer g-slist)))

(defun g-slist-next (list)
  (if (cffi:null-pointer-p list)
      (cffi:null-pointer)
      (cffi:foreign-slot-value list 'g-slist 'next)))

(defun g-slist-to-list (pointer &key (free t))
  (prog1
      (iter (for c initially pointer then (g-slist-next c))
            (until (cffi:null-pointer-p c))
	    (collect (cffi:convert-from-foreign 
                      (cffi:foreign-slot-value c 'g-slist 'data) :string)))
    (when free
      (g-slist-free pointer))))

;;
;; GError
;;

(cffi:defcstruct g-error
  "The GError structure contains information about an error that has occurred."
  (domain :uint32)
  (code :int)
  (message :string))

(cffi:defcfun g-error-free :void (g-error :pointer))

(define-condition gerror (error)
  ((domain :initarg :domain :reader gerror-domain)
   (code :initarg :code :reader gerror-code)
   (message :initarg :message :reader gerror-message))
  (:report (lambda (condition stream)
             (format stream "~A" (gerror-message condition)))))

(defun make-gerror-from-ptr (ptr)
  (make-condition 'gerror
                  :domain (cffi:foreign-slot-value ptr '(:struct g-error) 'domain)
                  :code (cffi:foreign-slot-value ptr '(:struct g-error) 'code)
                  :message (cffi:foreign-slot-value ptr '(:struct g-error) 'message)))

(defmacro with-gerror (err &body body)
  `(cffi:with-foreign-object (,err :pointer)
     (setf (cffi:mem-ref ,err :pointer) (cffi:null-pointer))
     (prog1
         (progn ,@body)
       (let ((e (cffi:mem-ref ,err :pointer)))
	 (unless (cffi:null-pointer-p e)
           (let ((condition (make-gerror-from-ptr e)))
             (g-error-free e)
             (error condition)))))))

(defmacro define-collection-getter (name get-count get-item)
  (let ((def-get-count (unless (listp get-count)
			 `(cffi:defcfun ,get-count :int (info info-ffi))))
	(get-count-name (if (listp get-count)
			    (first get-count)
			    get-count)))
    `(progn
       ,def-get-count
       (cffi:defcfun ,get-item info-ffi (info info-ffi) (n :int))
       (defun ,name (info)
	 (let ((n (,get-count-name info)))
	   (iter (for i from 0 below n)
		 (collect (info-ffi-finalize (,get-item info i)))))))))


(cffi:defbitfield connect-flags
    (:none 0)
  :after
  :swapped)

(cffi:defcfun g-signal-connect-data :ulong
  (instance :pointer)
  (detailed-signal :string)
  (c-handler :pointer)
  (data :pointer)
  (destroy-data :pointer)
  (connect-flags connect-flags))

#+sbcl (sb-ext::set-floating-point-modes :traps nil)
