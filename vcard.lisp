
(cl:defpackage :soiree-vcard
  (:use :common-lisp :parser-combinators :soiree :soiree-parse)
  (:shadow #:version? #:geo?))

(cl:in-package :soiree-vcard)

(defvar *vcard-namespace* "urn:ietf:params:xml:ns:vcard-4.0")

(defmacro with-vcard-namespace (&body body)
  `(xpath:with-namespaces ((nil *vcard-namespace*))
     ,@body))

(defvar *vcard-rng-pathname*
  (merge-pathnames #p"vcard-4_0.rnc" soiree-config:*base-directory*))

(defvar *vcard-rng-schema* (cxml-rng:parse-compact *vcard-rng-pathname*))

(defparameter *current-vcard-version* nil)

;;; Section 5: Parameters

;; 5.1 language
(defun param-language (params)
  (when-let (language
             (caadar (keep "language" params :test #'string-equal :key #'car)))
    (stp:append-child (stp:make-element "language" *vcard-namespace*)
                      (make-text-node language "language-tag"))))

;; 5.2 pref
(defun param-pref (params)
  (when-let (pref
             (caadar (keep "pref" params :test #'string-equal :key #'car)))
    (stp:append-child (stp:make-element "pref" *vcard-namespace*)
                      (make-text-node pref "integer"))))

;; Note that there is no section 5.3 in the spec!
;; 5.4 altid
(defun param-altid (params)
  (when-let (altid (caadar (keep "altid" params :test #'string-equal :key #'car)))
    (stp:append-child (stp:make-element "altid" *vcard-namespace*)
                      (make-text-node altid))))
;; 5.5 pid
(defun param-pid (params)
  (when-let (pids
             (mapcan #'second (keep "pid" params :test #'string-equal :key #'car)))
    (reduce (lambda (parent pid) (stp:append-child parent (make-text-node pid)))
            pids :initial-value (stp:make-element "pid" *vcard-namespace*))))

;; 5.6 type
(defparameter *types* '("work" "home"))

(defun param-type (params)
  (when-let (types
             (mapcan #'second (keep "type" params :test #'string-equal :key #'car)))
    (reduce (lambda (parent type)
              (when *strict-parsing*
                (unless (member type *types* :test #'string-equal)
                  (error "Unknown type: ~A" type)))
              (stp:append-child parent (make-text-node type)))
            types :initial-value (stp:make-element "type" *vcard-namespace*))))

;; 5.7 mediatype
(defun param-mediatype (params)
  (when-let (mediatype
             (caadar (keep "mediatype" params :test #'string-equal :key #'car)))
    (stp:append-child (stp:make-element "mediatype" *vcard-namespace*)
                      (make-text-node mediatype "text"))))

;; 5.8 calscale
(defparameter *calscales* '("gregorian"))

(defun param-calscale (params)
  (when-let (calscale
             (caadar (keep "calscale" params :test #'string-equal :key #'car)))
    (when *strict-parsing*
      (unless (member calscale *calscales* :test #'string-equal)
        (error "Unknown calscale: ~A" calscale)))
    (stp:append-child (stp:make-element "calscale" *vcard-namespace*)
                      (make-text-node calscale "text"))))


;; parameter utility routines
(defun add-params (param-list params)
  (remove nil (mapcar (lambda (x) (funcall x params)) param-list) :test 'eq))

(defun extract-parameters (params functions)
  (let ((param-element (stp:make-element "parameters" *vcard-namespace*)))
    (let ((param-children (add-params functions params)))
      (reduce #'stp:append-child param-children :initial-value param-element))))


(defun adr? ()
  (named-seq?
   (<- result (content-line? "ADR"))
   (destructuring-bind (group name params value)
       result
     (destructuring-bind (pobox ext street locality region code country)
         (split-string value :delimiter #\;)
       (reduce (lambda (parent child)
                 (add-fset-element-child parent child))
               (list (apply #'make-fset-text-nodes "pobox"
                            (split-string pobox))
                     (apply #'make-fset-text-nodes "ext"
                            (split-string ext))
                     (apply #'make-fset-text-nodes "street"
                            (split-string street))
                     (apply #'make-fset-text-nodes "locality"
                            (split-string locality))
                     (apply #'make-fset-text-nodes "region"
                            (split-string region))
                     (apply #'make-fset-text-nodes "code"
                            (split-string code))
                     (apply #'make-fset-text-nodes "country"
                            (split-string country)))
               :initial-value (make-fset-element "adr" *vcard-namespace*))))))

(defun anniversary? () (value-text-node? "ANNIVERSARY" "anniversary"))
(defun caladruri? () (value-text-node? "CALADRURI" "caladruri"))
(defun caluri? () (value-text-node? "CALURI" "caluri"))

;; fix me -- categories needs to accept multiple values
(defun categories? () (value-text-node? "CATEGORIES" "categories"))

(defun clientpidmap? () (value-text-node? "CLIENTPIDMAP" "clientpidmap"))
(defun email? () (value-text-node? "EMAIL" "email"))

(defun fburl? () (uri-text-node? "FBURL" "fburl"))

(defun impp? () (uri-text-node? "IMPP" "impp"))
(defun key? () (uri-text-node? "KEY" "key"))

;;; FIXME LANG is broken
(defun lang? () (value-text-node? "LANG" "lang"))

(defun member? () (value-text-node? "MEMBER" "member"))
(defun nickname? () (value-text-node? "NICKNAME" "nickname"))

(defun note? () (value-text-node? "NOTE" "note"))
(defun org? () (value-text-node? "ORG" "org"))
(defun photo? () (uri-text-node? "PHOTO" "photo"))

(defun related? () (value-text-node? "RELATED" "related"))
(defun rev? () (value-text-node? "REV" "rev"))

;; 6.1.3 source
(defun source? ()
  (named-seq?
   (<- result (content-line? "SOURCE"))
   (destructuring-bind (group name params value) result
     (let ((source-node (make-fset-element "source" *vcard-namespace*))
           (param-element (extract-parameters
                           params
                           (list #'param-altid #'param-pid #'param-pref
                                 #'param-mediatype))))
       (add-fset-element-child
        (if (plusp (stp:number-of-children param-element))
            (add-fset-element-child source-node param-element)
            source-node)
        (make-fset-text-node "uri" value))))))

;; 6.1.4 kind
(defun kind? () (value-text-node? "KIND" "kind"))

;; 6.2.1 fn
(defun fn? ()
  (named-seq?
   (<- result (content-line? "FN"))
   (destructuring-bind (group name params value) result
     (let ((fn-node (make-fset-element "fn" *vcard-namespace*))
           (param-element (extract-parameters
                           params
                           (list #'param-language #'param-altid #'param-pid
                                 #'param-pref #'param-type))))
       (add-fset-element-child
        (if (plusp (stp:number-of-children param-element))
            (add-fset-element-child fn-node param-element)
            fn-node)
        (make-fset-text-node "text" value))))))

;; 6.2.2 n
(defun n? ()
  (named-seq?
   (<- result (content-line? "N"))
   (destructuring-bind (group name params value)
       result
     (destructuring-bind (family-names
                          given-names
                          additional-names
                          honorific-prefixes
                          honorific-suffixes)
         (split-string value :delimiter #\;)
       (reduce (lambda (parent child)
                 (add-fset-element-child parent child))
               (list (apply #'make-fset-text-nodes "surname"
                            (split-string family-names))
                     (apply #'make-fset-text-nodes "given"
                            (split-string given-names))
                     (apply #'make-fset-text-nodes "additional"
                            (split-string additional-names))
                     (apply #'make-fset-text-nodes "prefix"
                            (split-string honorific-prefixes))
                     (apply #'make-fset-text-nodes "suffix"
                            (split-string honorific-suffixes)))
               :initial-value (make-fset-element "n" *vcard-namespace*))))))

;; 6.2.5 bday
;; FIXME: we should support the various data elements, instead of just text
(defun bday? ()
  (named-seq?
   (<- result (content-line? "BDAY"))
   (destructuring-bind (group name params value) result
     (let ((bday-node (make-fset-element "bday" *vcard-namespace*))
           (param-element (extract-parameters
                           params
                           (list #'param-altid #'param-calscale))))
       (add-fset-element-child
        (if (plusp (stp:number-of-children param-element))
            (add-fset-element-child bday-node param-element)
            bday-node)
        (make-fset-text-node "text" value))))))

(defun role? ()
  (named-seq?
   (<- result (content-line? "ROLE"))
   (destructuring-bind (group name params value) result
     (let ((role-node (make-fset-element "role" *vcard-namespace*))
           (param-element (extract-parameters
                           params
                           (list #'param-language #'param-altid #'param-pid
                                 #'param-pref #'param-type))))
       (add-fset-element-child
        (if (plusp (stp:number-of-children param-element))
            (add-fset-element-child role-node param-element)
            role-node)
        (make-fset-text-node "text" value))))))

(defun geo? ()
  (named-seq?
   (<- result (content-line? "GEO"))
   (destructuring-bind (group name params value) result
     (let ((geo-node (make-fset-element "geo" *vcard-namespace*))
           (param-element (extract-parameters
                           params
                           (list #'param-altid #'param-pid #'param-pref
                                 #'param-type #'param-mediatype))))
       (add-fset-element-child
        (if (plusp (stp:number-of-children param-element))
            (add-fset-element-child geo-node param-element)
            geo-node)
        (make-fset-text-node "uri" value))))))

(defun logo? ()
  (named-seq?
   (<- result (content-line? "LOGO"))
   (destructuring-bind (group name params value) result
     (let ((logo-node (make-fset-element "logo" *vcard-namespace*))
           (param-element (extract-parameters
                           params
                           (list #'param-language #'param-altid #'param-pid
                                 #'param-pref #'param-type #'param-mediatype))))
       (add-fset-element-child
        (if (plusp (stp:number-of-children param-element))
            (add-fset-element-child logo-node param-element)
            logo-node)
        (make-fset-text-node "uri" value))))))

(defun gender? () (value-text-node? "GENDER" "gender"))
(defun sound? () (value-text-node? "SOUND" "sound"))

(defun make-pref-element (&optional (value 1))
  (stp:append-child
   (stp:make-element "pref" *vcard-namespace*)
   (stp:append-child
    (stp:make-element "integer" *vcard-namespace*)
    (stp:make-text (format nil "~A" value)))))

(defparameter *tel-types* '("work" "home" "text" "voice" "fax"
                            "cell" "video" "pager""textphone"))

(defun tel? ()
  (named-seq?
   (<- result (content-line? "TEL"))
   (destructuring-bind (group name params value) result
     (let ((tel-node (make-fset-element "tel" *vcard-namespace*))
           (param-element (stp:make-element "parameters" *vcard-namespace*))
           (types (mapcan #'second
                          (keep "type" params :test #'string-equal :key #'car))))
       (cond ((equal *current-vcard-version* "3.0")
              (when (member "pref" types :test #'string-equal)
                (stp:append-child param-element (make-pref-element)))))
       (let ((tel-types (intersection types *tel-types* :test #'string-equal)))
         (when tel-types
           (let ((type-element (stp:make-element "type" *vcard-namespace*)))
             (reduce
              (lambda (parent child)
                (stp:append-child parent
                                  (make-text-node (string-downcase child))))
              tel-types
              :initial-value type-element)
             (stp:append-child param-element type-element))))
       (add-fset-element-child
        (if (plusp (stp:number-of-children param-element))
            (add-fset-element-child tel-node param-element)
            tel-node)
        (add-fset-element-child
         (make-fset-element "text" *vcard-namespace*)
         (make-fset-text value)))))))

(defun title? ()
  (named-seq?
   (<- result (content-line? "TITLE"))
   (destructuring-bind (group name params value) result
     (let ((title-node (make-fset-element "title" *vcard-namespace*))
           (param-element (extract-parameters
                           params
                           (list #'param-language #'param-altid #'param-pid
                                 #'param-pref #'param-type))))
       (add-fset-element-child
        (if (plusp (stp:number-of-children param-element))
            (add-fset-element-child title-node param-element)
            title-node)
        (make-fset-text-node "text" value))))))

(defun tz? () (value-text-node? "TZ" "tz"))

(defun version? () 
  (named-seq?
   (<- result (content-line? "VERSION"))
   (destructuring-bind (group name params value)
       result
     (setf *current-vcard-version* value)
     nil)))

(defun vcard? ()
  (named-seq?
   "BEGIN" ":" "VCARD" #\Return #\Newline
   (<- content (many1?
                (choices1
                 (adr?)
                 (anniversary?)
                 (bday?)
                 (caladruri?)
                 (caluri?)
                 (categories?)

                 (clientpidmap?) (email?) (fburl?)

                 (fn?) (geo?) (impp?) (key?)
                 
                 (kind?) (lang?) (logo?)

                 (member?) (n?) (nickname?)

                 (note?) (org?) (photo?)

                 (prodid?) (related?) (rev?)

                 (role?) (gender?) (sound?)

                 (source?) (tel?) (title?)

                 (tz?) (uid?) (url?)

                 (x-name-line?)
                 
                 (version?))))

   "END" ":" "VCARD" #\Return #\Newline
   (fset:reduce (lambda (element x)
                  (if (and x (not (consp x)))
                      (add-fset-element-child element x)
                      element))
                content
                :initial-value (make-fset-element "vcard" *vcard-namespace*))))

(defun parse-vcard (str)
  (let ((*default-namespace* *vcard-namespace*)
        (*current-vcard-version* nil))
    (stp:make-document
     (fset:reduce (lambda (element x)
                    (stp:append-child
                     element
                     (unwrap-stp-element x)))
                  (parse-string* (many1? (vcard?)) str)
                  :initial-value
                  (let ((element (stp:make-element "vcards" *vcard-namespace*)))
                    (cxml-stp:add-extra-namespace element "" *vcard-namespace*)
                    element)))))
