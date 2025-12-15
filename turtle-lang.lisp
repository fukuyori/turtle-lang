;;;; turtle-lang-full.lisp
;;;; タートルグラフィックス言語インタプリタ（完全版）
;;;; 
;;;; 機能一覧：
;;;; - 基本コマンド: forward, back, right, left, penup, pendown, home
;;;; - 拡張コマンド: setxy, setheading, circle, arc, pencolor, pensize
;;;; - 制御構造: repeat, while, for, if, ifelse
;;;; - 手続き: to...end, stop, output
;;;; - 変数: make, local
;;;; - 算術演算: + - * / %
;;;; - 比較演算: = < > <= >= <>
;;;; - 論理演算: and, or, not
;;;; - 状態取得: xcor, ycor, heading, pendown?
;;;; - リスト: list, first, last, butfirst, butlast, item, count, fput, lput
;;;; - 入出力: print, type
;;;; - その他: clearscreen, hideturtle, showturtle

;;; ========================================
;;; 1. ユーティリティ
;;; ========================================

(defun normalize-zero (x)
  "極小値を0に正規化"
  (if (< (abs x) 1.0d-10) 0.0 x))

(defun deg-to-rad (degrees)
  "度をラジアンに変換"
  (* degrees (/ pi 180.0)))

;;; ========================================
;;; 2. トークン定義
;;; ========================================

(defstruct token
  type      ; トークンの種類
  value     ; トークンの値
  line      ; 行番号
  column)   ; 列番号

;; トークンの種類:
;; :word      - 単語（コマンド名、手続き名）
;; :number    - 数値
;; :string    - 文字列 "..."
;; :param     - パラメータ参照 :name
;; :lbracket  - [
;; :rbracket  - ]
;; :lparen    - (
;; :rparen    - )
;; :operator  - 演算子 + - * / % = < > <= >= <>
;; :newline   - 改行
;; :eof       - ファイル終端

;;; ========================================
;;; 3. レキサー
;;; ========================================

(defstruct lexer
  input
  (pos 0)
  len
  (line 1)
  (column 1))

(defun make-lexer-from-string (input)
  (make-lexer :input input :pos 0 :len (length input)))

(defun current-char (lex)
  (when (< (lexer-pos lex) (lexer-len lex))
    (char (lexer-input lex) (lexer-pos lex))))

(defun peek-char-at (lex &optional (offset 1))
  (let ((pos (+ (lexer-pos lex) offset)))
    (when (< pos (lexer-len lex))
      (char (lexer-input lex) pos))))

(defun advance (lex)
  (let ((ch (current-char lex)))
    (when ch
      (if (eql ch #\Newline)
          (progn (incf (lexer-line lex))
                 (setf (lexer-column lex) 1))
          (incf (lexer-column lex)))
      (incf (lexer-pos lex)))))

(defun whitespace-p (ch)
  (member ch '(#\Space #\Tab #\Return)))

(defun skip-whitespace (lex)
  (loop while (and (current-char lex) (whitespace-p (current-char lex)))
        do (advance lex)))

(defun skip-comment (lex)
  (when (eql (current-char lex) #\;)
    (loop while (and (current-char lex)
                     (not (eql (current-char lex) #\Newline)))
          do (advance lex))))

(defun skip-whitespace-and-comments (lex)
  (loop (skip-whitespace lex)
        (if (eql (current-char lex) #\;)
            (skip-comment lex)
            (return))))

(defun read-number (lex)
  (let ((start (lexer-pos lex))
        (has-dot nil))
    (when (eql (current-char lex) #\-)
      (advance lex))
    (loop while (and (current-char lex)
                     (or (digit-char-p (current-char lex))
                         (and (eql (current-char lex) #\.)
                              (not has-dot))))
          do (when (eql (current-char lex) #\.)
               (setf has-dot t))
             (advance lex))
    (let ((str (subseq (lexer-input lex) start (lexer-pos lex))))
      (if has-dot
          (read-from-string str)
          (parse-integer str)))))

(defun word-char-p (ch)
  (or (alphanumericp ch)
      (member ch '(#\- #\_ #\? #\!))))

(defun read-word (lex)
  (let ((start (lexer-pos lex)))
    (loop while (and (current-char lex) (word-char-p (current-char lex)))
          do (advance lex))
    (subseq (lexer-input lex) start (lexer-pos lex))))

(defun read-param (lex)
  (advance lex)  ; skip ':'
  (read-word lex))

(defun read-string (lex)
  "Read a double-quoted string like \"hello world\""
  (advance lex)  ; skip opening "
  (let ((start (lexer-pos lex)))
    (loop while (and (current-char lex)
                     (not (eql (current-char lex) #\")))
          do (when (eql (current-char lex) #\\)
               (advance lex))  ; skip escape
             (advance lex))
    (let ((str (subseq (lexer-input lex) start (lexer-pos lex))))
      (advance lex)  ; skip closing "
      str)))

(defun read-quoted-word (lex)
  "Read a quoted word like \"word (Logo style - no closing quote)"
  (advance lex)  ; skip "
  (let ((start (lexer-pos lex)))
    (loop while (and (current-char lex)
                     (word-char-p (current-char lex)))
          do (advance lex))
    (subseq (lexer-input lex) start (lexer-pos lex))))

(defun operator-char-p (ch)
  (member ch '(#\+ #\- #\* #\/ #\% #\= #\< #\>)))

(defun read-operator (lex)
  (let ((ch (current-char lex)))
    (advance lex)
    (cond
      ;; Two-character operators
      ((and (eql ch #\<) (eql (current-char lex) #\=))
       (advance lex) "<=")
      ((and (eql ch #\>) (eql (current-char lex) #\=))
       (advance lex) ">=")
      ((and (eql ch #\<) (eql (current-char lex) #\>))
       (advance lex) "<>")
      ;; Single-character operators
      (t (string ch)))))

(defun next-token (lex)
  (skip-whitespace-and-comments lex)
  (let ((line (lexer-line lex))
        (col (lexer-column lex))
        (ch (current-char lex)))
    (flet ((tok (type value)
             (make-token :type type :value value :line line :column col)))
      (cond
        ((null ch) (tok :eof nil))
        ((eql ch #\Newline) (advance lex) (tok :newline nil))
        ((eql ch #\[) (advance lex) (tok :lbracket "["))
        ((eql ch #\]) (advance lex) (tok :rbracket "]"))
        ((eql ch #\() (advance lex) (tok :lparen "("))
        ((eql ch #\)) (advance lex) (tok :rparen ")"))
        ((eql ch #\:) (tok :param (read-param lex)))
        ((eql ch #\")
         ;; Check next character to determine string type
         (let ((next-ch (peek-char-at lex)))  ; default offset is 1
           (if (and next-ch (or (alpha-char-p next-ch) (eql next-ch #\_)))
               ;; "word style (Logo convention - no closing quote)
               (tok :string (read-quoted-word lex))
               ;; "string with spaces" style or empty string
               (tok :string (read-string lex)))))
        ;; Numbers (including negative)
        ((or (digit-char-p ch)
             (and (eql ch #\-)
                  (peek-char-at lex 0)
                  (digit-char-p (peek-char-at lex 0))))
         (tok :number (read-number lex)))
        ;; Operators (but not negative numbers)
        ((and (operator-char-p ch)
              (not (and (eql ch #\-)
                        (peek-char-at lex 0)
                        (digit-char-p (peek-char-at lex 0)))))
         (tok :operator (read-operator lex)))
        ;; Words
        ((alpha-char-p ch)
         (tok :word (read-word lex)))
        (t (error "Unexpected character '~A' at line ~A, column ~A"
                  ch line col))))))

(defun tokenize (input)
  (let ((lex (make-lexer-from-string input))
        (tokens '()))
    (loop for tok = (next-token lex)
          do (push tok tokens)
          until (eq (token-type tok) :eof))
    (nreverse tokens)))

;;; ========================================
;;; 4. パーサー
;;; ========================================

(defstruct parser
  tokens
  (pos 0))

(defun current-token (p)
  (nth (parser-pos p) (parser-tokens p)))

(defun peek-token (p &optional (offset 1))
  (nth (+ (parser-pos p) offset) (parser-tokens p)))

(defun consume (p)
  (prog1 (current-token p)
    (incf (parser-pos p))))

(defun check-token (p type &optional value)
  (let ((tok (current-token p)))
    (and (eq (token-type tok) type)
         (or (null value)
             (equal (token-value tok) value)))))

(defun check-word (p word)
  (check-token p :word word))

(defun expect (p type &optional value)
  (if (check-token p type value)
      (consume p)
      (let ((tok (current-token p)))
        (error "Expected ~A~@[ '~A'~], got ~A '~A' at line ~A"
               type value (token-type tok) (token-value tok) (token-line tok)))))

(defun skip-newlines (p)
  (loop while (check-token p :newline) do (consume p)))

;;; --- コマンド名の正規化 ---

(defparameter *command-aliases*
  '(("fd" . "forward") ("bk" . "back") ("rt" . "right") ("lt" . "left")
    ("pu" . "penup") ("pd" . "pendown") ("pc" . "pencolor") ("ps" . "pensize")
    ("cs" . "clearscreen") ("ht" . "hideturtle") ("st" . "showturtle")
    ("seth" . "setheading") ("setx" . "setx") ("sety" . "sety")
    ("bf" . "butfirst") ("bl" . "butlast") ("op" . "output")))

(defparameter *keywords*
  '("forward" "back" "right" "left" "penup" "pendown" "home"
    "setxy" "setheading" "setx" "sety" "circle" "arc"
    "pencolor" "pensize" "clearscreen" "hideturtle" "showturtle"
    "repeat" "while" "for" "if" "ifelse"
    "to" "end" "stop" "output"
    "make" "local" "thing"
    "print" "type" "show"
    "list" "first" "last" "butfirst" "butlast" "item" "count" "fput" "lput"
    "word" "sentence"
    "and" "or" "not"
    "xcor" "ycor" "heading" "pendown?" "towards"
    "random" "sqrt" "abs" "int" "round" "sin" "cos" "tan" "atan"))

(defun normalize-command (name)
  (let ((cmd (string-downcase name)))
    (or (cdr (assoc cmd *command-aliases* :test #'string=))
        cmd)))

;;; --- 式パーサー（演算子優先順位法） ---

(defun parse-expression (p)
  "Parse an expression with operator precedence"
  (parse-or-expr p))

(defun parse-or-expr (p)
  (let ((left (parse-and-expr p)))
    (loop while (and (check-token p :word)
                     (string= (normalize-command (token-value (current-token p))) "or"))
          do (consume p)
             (setf left (list :OR left (parse-and-expr p))))
    left))

(defun parse-and-expr (p)
  (let ((left (parse-comparison-expr p)))
    (loop while (and (check-token p :word)
                     (string= (normalize-command (token-value (current-token p))) "and"))
          do (consume p)
             (setf left (list :AND left (parse-comparison-expr p))))
    left))

(defun parse-comparison-expr (p)
  (let ((left (parse-additive-expr p)))
    (when (check-token p :operator)
      (let ((op (token-value (current-token p))))
        (when (member op '("=" "<" ">" "<=" ">=" "<>") :test #'string=)
          (consume p)
          (let ((right (parse-additive-expr p)))
            (setf left (list (intern (string-upcase
                                       (case (intern op :keyword)
                                         (:|=| "EQ")
                                         (:|<| "LT")
                                         (:|>| "GT")
                                         (:|<=| "LE")
                                         (:|>=| "GE")
                                         (:|<>| "NE")))
                                     :keyword)
                             left right))))))
    left))

(defun parse-additive-expr (p)
  (let ((left (parse-multiplicative-expr p)))
    (loop while (and (check-token p :operator)
                     (member (token-value (current-token p)) '("+" "-") :test #'string=))
          do (let ((op (token-value (consume p))))
               (setf left (list (if (string= op "+") :ADD :SUB)
                                left (parse-multiplicative-expr p)))))
    left))

(defun parse-multiplicative-expr (p)
  (let ((left (parse-unary-expr p)))
    (loop while (and (check-token p :operator)
                     (member (token-value (current-token p)) '("*" "/" "%") :test #'string=))
          do (let ((op (token-value (consume p))))
               (setf left (list (cond ((string= op "*") :MUL)
                                      ((string= op "/") :DIV)
                                      ((string= op "%") :MOD))
                                left (parse-unary-expr p)))))
    left))

(defun parse-unary-expr (p)
  (cond
    ;; Unary minus
    ((check-token p :operator "-")
     (consume p)
     (list :NEG (parse-unary-expr p)))
    ;; not operator
    ((and (check-token p :word)
          (string= (normalize-command (token-value (current-token p))) "not"))
     (consume p)
     (list :NOT (parse-unary-expr p)))
    (t (parse-primary-expr p))))

(defun parse-primary-expr (p)
  (cond
    ;; Number literal
    ((check-token p :number)
     (token-value (consume p)))
    
    ;; String literal
    ((check-token p :string)
     (list :STRING (token-value (consume p))))
    
    ;; Parameter reference
    ((check-token p :param)
     (list :VAR (token-value (consume p))))
    
    ;; Parenthesized expression
    ((check-token p :lparen)
     (consume p)
     (let ((expr (parse-expression p)))
       (expect p :rparen)
       expr))
    
    ;; List literal or block used as expression
    ((check-token p :lbracket)
     (parse-list-literal p))
    
    ;; Built-in functions and value reporters
    ((check-token p :word)
     (let ((word (normalize-command (token-value (current-token p)))))
       (cond
         ;; State reporters (no arguments)
         ((member word '("xcor" "ycor" "heading" "pendown?") :test #'string=)
          (consume p)
          (list (intern (string-upcase word) :keyword)))
         
         ;; One-argument functions
         ((member word '("random" "sqrt" "abs" "int" "round"
                         "sin" "cos" "tan" "first" "last" "butfirst" "butlast"
                         "count" "not" "thing" "minus") :test #'string=)
          (consume p)
          (list (intern (string-upcase word) :keyword) (parse-expression p)))
         
         ;; Two-argument functions
         ((member word '("sum" "difference" "product" "quotient" "remainder"
                         "power" "item" "word" "atan" "towards"
                         "fput" "lput") :test #'string=)
          (consume p)
          (list (intern (string-upcase word) :keyword)
                (parse-expression p)
                (parse-expression p)))
         
         ;; List constructor (variable arguments)
         ((string= word "list")
          (consume p)
          (let ((items '()))
            ;; Collect items until we hit something that's not an expression starter
            (loop while (or (check-token p :number)
                            (check-token p :string)
                            (check-token p :param)
                            (check-token p :lbracket)
                            (check-token p :lparen)
                            (and (check-token p :word)
                                 (not (member (normalize-command (token-value (current-token p)))
                                              *keywords* :test #'string=))))
                  do (push (parse-expression p) items))
            (list :LIST (nreverse items))))
         
         ;; sentence constructor
         ((string= word "sentence")
          (consume p)
          (list :SENTENCE (parse-expression p) (parse-expression p)))
         
         ;; Unknown word - might be a procedure call that returns a value
         (t
          (if (member word *keywords* :test #'string=)
              (error "Unexpected keyword '~A' in expression" word)
              ;; User-defined function call
              (progn
                (consume p)
                (let ((args '()))
                  (loop while (or (check-token p :number)
                                  (check-token p :string)
                                  (check-token p :param)
                                  (check-token p :lbracket)
                                  (check-token p :lparen))
                        do (push (parse-expression p) args))
                  (list :FUNCALL word (nreverse args)))))))))
    
    (t (error "Expected expression at line ~A, got ~A"
              (token-line (current-token p))
              (token-type (current-token p))))))

(defun parse-list-literal (p)
  "Parse a list literal [item item ...]"
  (expect p :lbracket)
  (let ((items '()))
    (loop until (check-token p :rbracket)
          do (skip-newlines p)
             (unless (check-token p :rbracket)
               (push (parse-list-item p) items)))
    (expect p :rbracket)
    (list :LITERAL-LIST (nreverse items))))

(defun parse-list-item (p)
  "Parse an item inside a list literal"
  (cond
    ((check-token p :number) (token-value (consume p)))
    ((check-token p :string) (list :STRING (token-value (consume p))))
    ((check-token p :param) (list :VAR (token-value (consume p))))
    ((check-token p :word) (list :STRING (token-value (consume p))))
    ((check-token p :lbracket) (parse-list-literal p))
    (t (error "Unexpected token in list at line ~A" (token-line (current-token p))))))

;;; --- 文パーサー ---

(defun parse-expression-block (p)
  "Parse a block [...] containing a single expression (for while condition)"
  (expect p :lbracket)
  (skip-newlines p)
  (let ((expr (parse-expression p)))
    (skip-newlines p)
    (expect p :rbracket)
    expr))

(defun parse-block (p)
  "Parse a block [...] of statements"
  (expect p :lbracket)
  (skip-newlines p)
  (let ((stmts '()))
    (loop until (check-token p :rbracket)
          do (skip-newlines p)
             (unless (check-token p :rbracket)
               (push (parse-statement p) stmts))
             (skip-newlines p))
    (expect p :rbracket)
    (nreverse stmts)))

(defun parse-parameters (p)
  "Parse parameter list for procedure definition"
  (let ((params '()))
    (loop while (check-token p :param)
          do (push (token-value (consume p)) params))
    (nreverse params)))

(defun parse-procedure-body (p)
  "Parse procedure body until 'end'"
  (skip-newlines p)
  (let ((stmts '()))
    (loop until (and (check-token p :word)
                     (string= (normalize-command (token-value (current-token p))) "end"))
          do (push (parse-statement p) stmts)
             (skip-newlines p))
    (expect p :word)  ; consume "end"
    (nreverse stmts)))

(defun parse-statement (p)
  "Parse a single statement"
  (skip-newlines p)
  
  (unless (check-token p :word)
    (error "Expected command at line ~A, got ~A"
           (token-line (current-token p))
           (token-type (current-token p))))
  
  (let ((cmd (normalize-command (token-value (current-token p)))))
    (consume p)
    
    (cond
      ;; Movement commands (1 arg)
      ((member cmd '("forward" "back" "right" "left") :test #'string=)
       (list (intern (string-upcase cmd) :keyword) (parse-expression p)))
      
      ;; Pen commands (no args)
      ((string= cmd "penup") '(:PENUP))
      ((string= cmd "pendown") '(:PENDOWN))
      ((string= cmd "home") '(:HOME))
      ((string= cmd "clearscreen") '(:CLEARSCREEN))
      ((string= cmd "hideturtle") '(:HIDETURTLE))
      ((string= cmd "showturtle") '(:SHOWTURTLE))
      
      ;; Pen attributes (1 arg)
      ((string= cmd "pencolor")
       (list :PENCOLOR (parse-expression p)))
      ((string= cmd "pensize")
       (list :PENSIZE (parse-expression p)))
      
      ;; Position/heading commands
      ((string= cmd "setxy")
       (list :SETXY (parse-expression p) (parse-expression p)))
      ((string= cmd "setx")
       (list :SETX (parse-expression p)))
      ((string= cmd "sety")
       (list :SETY (parse-expression p)))
      ((string= cmd "setheading")
       (list :SETHEADING (parse-expression p)))
      
      ;; Circle/Arc
      ((string= cmd "circle")
       (list :CIRCLE (parse-expression p)))
      ((string= cmd "arc")
       (list :ARC (parse-expression p) (parse-expression p)))
      
      ;; repeat statement
      ((string= cmd "repeat")
       (list :REPEAT (parse-expression p) (parse-block p)))
      
      ;; while statement: while [condition] [body]
      ((string= cmd "while")
       (list :WHILE (parse-expression-block p) (parse-block p)))
      
      ;; for statement: for "var start end [body] or for "var start end step [body]
      ((string= cmd "for")
       (let* ((var (token-value (expect p :string)))
              (start (parse-expression p))
              (end (parse-expression p))
              (step-or-body (if (check-token p :lbracket)
                                nil
                                (parse-expression p)))
              (body (parse-block p)))
         (if step-or-body
             (list :FOR var start end step-or-body body)
             (list :FOR var start end 1 body))))
      
      ;; if statement
      ((string= cmd "if")
       (list :IF (parse-expression p) (parse-block p)))
      
      ;; ifelse statement
      ((string= cmd "ifelse")
       (list :IFELSE (parse-expression p) (parse-block p) (parse-block p)))
      
      ;; Procedure definition
      ((string= cmd "to")
       (let* ((name (string-downcase (token-value (expect p :word))))
              (params (parse-parameters p))
              (body (parse-procedure-body p)))
         (list :DEFINE name params body)))
      
      ;; stop (exit procedure)
      ((string= cmd "stop")
       '(:STOP))
      
      ;; output (return value from procedure)
      ((string= cmd "output")
       (list :OUTPUT (parse-expression p)))
      
      ;; Variable assignment
      ((string= cmd "make")
       (let ((name (token-value (expect p :string))))
         (list :MAKE name (parse-expression p))))
      
      ;; Local variable
      ((string= cmd "local")
       (let ((name (token-value (expect p :string))))
         (list :LOCAL name)))
      
      ;; Output commands
      ((string= cmd "print")
       (list :PRINT (parse-expression p)))
      ((string= cmd "type")
       (list :TYPE (parse-expression p)))
      ((string= cmd "show")
       (list :SHOW (parse-expression p)))
      
      ;; Unknown command - procedure call
      (t
       (let ((args '()))
         (loop while (or (check-token p :number)
                         (check-token p :string)
                         (check-token p :param)
                         (check-token p :lbracket)
                         (check-token p :lparen)
                         (check-token p :operator "-"))
               do (push (parse-expression p) args))
         (list :CALL cmd (nreverse args)))))))

(defun parse-program (p)
  "Parse entire program"
  (let ((stmts '()))
    (loop until (check-token p :eof)
          do (skip-newlines p)
             (unless (check-token p :eof)
               (push (parse-statement p) stmts))
             (skip-newlines p))
    (nreverse stmts)))

(defun parse (input)
  "Parse source code into AST"
  (parse-program (make-parser :tokens (tokenize input))))

;;; ========================================
;;; 5. タートル状態
;;; ========================================

(defstruct turtle
  (x 0.0)
  (y 0.0)
  (angle 0.0)         ; 0=up, clockwise
  (pen-down t)
  (pen-color "black")
  (pen-size 1)
  (visible t)
  (lines '()))        ; List of line segments

(defstruct line-segment
  x1 y1 x2 y2
  color
  size)

(defun turtle-forward (turtle dist)
  (let* ((rad (deg-to-rad (turtle-angle turtle)))
         (dx (* dist (sin rad)))
         (dy (* dist (cos rad)))
         (ox (turtle-x turtle))
         (oy (turtle-y turtle))
         (nx (+ ox dx))
         (ny (+ oy dy)))
    (when (turtle-pen-down turtle)
      (push (make-line-segment :x1 ox :y1 oy :x2 nx :y2 ny
                               :color (turtle-pen-color turtle)
                               :size (turtle-pen-size turtle))
            (turtle-lines turtle)))
    (setf (turtle-x turtle) nx
          (turtle-y turtle) ny)))

(defun turtle-back (turtle dist)
  (turtle-forward turtle (- dist)))

(defun turtle-right (turtle deg)
  (setf (turtle-angle turtle)
        (mod (+ (turtle-angle turtle) deg) 360.0)))

(defun turtle-left (turtle deg)
  (turtle-right turtle (- deg)))

(defun turtle-setxy (turtle x y)
  (let ((ox (turtle-x turtle))
        (oy (turtle-y turtle)))
    (when (turtle-pen-down turtle)
      (push (make-line-segment :x1 ox :y1 oy :x2 x :y2 y
                               :color (turtle-pen-color turtle)
                               :size (turtle-pen-size turtle))
            (turtle-lines turtle)))
    (setf (turtle-x turtle) (float x)
          (turtle-y turtle) (float y))))

(defun turtle-setx (turtle x)
  (turtle-setxy turtle x (turtle-y turtle)))

(defun turtle-sety (turtle y)
  (turtle-setxy turtle (turtle-x turtle) y))

(defun turtle-setheading (turtle angle)
  (setf (turtle-angle turtle) (mod (float angle) 360.0)))

(defun turtle-home (turtle)
  (turtle-setxy turtle 0.0 0.0)
  (setf (turtle-angle turtle) 0.0))

(defun turtle-circle (turtle radius)
  "Draw a circle by approximating with small line segments"
  (let ((steps 36)
        (step-angle (/ 360.0 36)))
    (dotimes (i steps)
      (turtle-forward turtle (* 2 pi radius (/ 1.0 steps)))
      (turtle-right turtle step-angle))))

(defun turtle-arc (turtle angle radius)
  "Draw an arc"
  (let* ((steps (max 1 (round (abs angle) 10)))
         (step-angle (/ angle steps))
         (step-dist (* 2 pi radius (/ (abs angle) 360.0) (/ 1.0 steps))))
    (dotimes (i steps)
      (turtle-forward turtle step-dist)
      (turtle-right turtle step-angle))))

(defun turtle-clearscreen (turtle)
  (setf (turtle-lines turtle) '())
  (setf (turtle-x turtle) 0.0
        (turtle-y turtle) 0.0
        (turtle-angle turtle) 0.0))

;;; ========================================
;;; 6. 環境（スコープ管理）
;;; ========================================

(defstruct environment
  (bindings (make-hash-table :test 'equal))
  (parent nil))

(defun env-lookup (env name)
  "Look up variable in environment chain"
  (multiple-value-bind (val found)
      (gethash name (environment-bindings env))
    (if found
        val
        (if (environment-parent env)
            (env-lookup (environment-parent env) name)
            (error "Undefined variable: ~A" name)))))

(defun env-lookup-safe (env name)
  "Look up variable, return nil if not found"
  (multiple-value-bind (val found)
      (gethash name (environment-bindings env))
    (if found
        (values val t)
        (if (environment-parent env)
            (env-lookup-safe (environment-parent env) name)
            (values nil nil)))))

(defun env-set (env name value)
  "Set variable in nearest scope where it exists, or current scope"
  (multiple-value-bind (val found)
      (gethash name (environment-bindings env))
    (declare (ignore val))
    (if found
        (setf (gethash name (environment-bindings env)) value)
        (if (environment-parent env)
            (multiple-value-bind (pval pfound)
                (env-lookup-safe (environment-parent env) name)
              (declare (ignore pval))
              (if pfound
                  (env-set (environment-parent env) name value)
                  (setf (gethash name (environment-bindings env)) value)))
            (setf (gethash name (environment-bindings env)) value)))))

(defun env-define (env name value)
  "Define variable in current scope"
  (setf (gethash name (environment-bindings env)) value))

;;; ========================================
;;; 7. 手続き定義
;;; ========================================

(defstruct procedure
  name
  params
  body)

;;; ========================================
;;; 8. インタプリタ
;;; ========================================

(defstruct interpreter
  (turtle (make-turtle))
  (procedures (make-hash-table :test 'equal))
  (global-env (make-environment))
  (output-buffer '()))

;; Special condition for stop/output
(define-condition procedure-return ()
  ((value :initarg :value :reader return-value)))

(defun interp-error (fmt &rest args)
  (error "Runtime error: ~?" fmt args))

;;; --- Expression evaluation ---

(defun eval-expr (expr interp env)
  "Evaluate an expression"
  (cond
    ;; Numbers are self-evaluating
    ((numberp expr) expr)
    
    ;; Strings
    ((stringp expr) expr)
    
    ;; Lists (AST nodes)
    ((listp expr)
     (case (first expr)
       ;; String literal
       (:STRING (second expr))
       
       ;; Variable reference
       (:VAR (env-lookup env (second expr)))
       
       ;; Arithmetic
       (:ADD (+ (eval-expr (second expr) interp env)
                (eval-expr (third expr) interp env)))
       (:SUB (- (eval-expr (second expr) interp env)
                (eval-expr (third expr) interp env)))
       (:MUL (* (eval-expr (second expr) interp env)
                (eval-expr (third expr) interp env)))
       (:DIV (let ((divisor (eval-expr (third expr) interp env)))
               (if (zerop divisor)
                   (interp-error "Division by zero")
                   (/ (eval-expr (second expr) interp env) divisor))))
       (:MOD (mod (eval-expr (second expr) interp env)
                  (eval-expr (third expr) interp env)))
       (:NEG (- (eval-expr (second expr) interp env)))
       
       ;; Comparison
       (:EQ (if (equal (eval-expr (second expr) interp env)
                       (eval-expr (third expr) interp env))
                "true" "false"))
       (:LT (if (< (eval-expr (second expr) interp env)
                   (eval-expr (third expr) interp env))
                "true" "false"))
       (:GT (if (> (eval-expr (second expr) interp env)
                   (eval-expr (third expr) interp env))
                "true" "false"))
       (:LE (if (<= (eval-expr (second expr) interp env)
                    (eval-expr (third expr) interp env))
                "true" "false"))
       (:GE (if (>= (eval-expr (second expr) interp env)
                    (eval-expr (third expr) interp env))
                "true" "false"))
       (:NE (if (not (equal (eval-expr (second expr) interp env)
                            (eval-expr (third expr) interp env)))
                "true" "false"))
       
       ;; Logical
       (:AND (if (and (truep (eval-expr (second expr) interp env))
                      (truep (eval-expr (third expr) interp env)))
                 "true" "false"))
       (:OR (if (or (truep (eval-expr (second expr) interp env))
                    (truep (eval-expr (third expr) interp env)))
                "true" "false"))
       (:NOT (if (truep (eval-expr (second expr) interp env))
                 "false" "true"))
       
       ;; State reporters
       (:XCOR (turtle-x (interpreter-turtle interp)))
       (:YCOR (turtle-y (interpreter-turtle interp)))
       (:HEADING (turtle-angle (interpreter-turtle interp)))
       (:PENDOWN? (if (turtle-pen-down (interpreter-turtle interp))
                      "true" "false"))
       
       ;; Math functions
       (:RANDOM (random (truncate (eval-expr (second expr) interp env))))
       (:SQRT (sqrt (eval-expr (second expr) interp env)))
       (:ABS (abs (eval-expr (second expr) interp env)))
       (:INT (truncate (eval-expr (second expr) interp env)))
       (:ROUND (round (eval-expr (second expr) interp env)))
       (:SIN (sin (deg-to-rad (eval-expr (second expr) interp env))))
       (:COS (cos (deg-to-rad (eval-expr (second expr) interp env))))
       (:TAN (tan (deg-to-rad (eval-expr (second expr) interp env))))
       (:ATAN (if (third expr)
                  (/ (* 180.0 (atan (eval-expr (second expr) interp env)
                                    (eval-expr (third expr) interp env)))
                     pi)
                  (/ (* 180.0 (atan (eval-expr (second expr) interp env)))
                     pi)))
       (:MINUS (- (eval-expr (second expr) interp env)))
       (:POWER (expt (eval-expr (second expr) interp env)
                     (eval-expr (third expr) interp env)))
       
       ;; Alternative arithmetic (Logo style)
       (:SUM (+ (eval-expr (second expr) interp env)
                (eval-expr (third expr) interp env)))
       (:DIFFERENCE (- (eval-expr (second expr) interp env)
                       (eval-expr (third expr) interp env)))
       (:PRODUCT (* (eval-expr (second expr) interp env)
                    (eval-expr (third expr) interp env)))
       (:QUOTIENT (/ (eval-expr (second expr) interp env)
                     (eval-expr (third expr) interp env)))
       (:REMAINDER (mod (eval-expr (second expr) interp env)
                        (eval-expr (third expr) interp env)))
       
       ;; thing (variable lookup)
       (:THING (env-lookup env (eval-expr (second expr) interp env)))
       
       ;; towards (angle to point)
       (:TOWARDS
        (let ((tx (eval-expr (second expr) interp env))
              (ty (eval-expr (third expr) interp env))
              (turtle (interpreter-turtle interp)))
          (let ((dx (- tx (turtle-x turtle)))
                (dy (- ty (turtle-y turtle))))
            (mod (- 90 (/ (* 180 (atan dy dx)) pi)) 360))))
       
       ;; List operations
       (:LIST
        (mapcar (lambda (e) (eval-expr e interp env)) (second expr)))
       
       (:LITERAL-LIST
        (mapcar (lambda (e)
                  (if (and (listp e) (eq (first e) :VAR))
                      (eval-expr e interp env)
                      (if (and (listp e) (eq (first e) :STRING))
                          (second e)
                          (if (and (listp e) (eq (first e) :LITERAL-LIST))
                              (eval-expr e interp env)
                              e))))
                (second expr)))
       
       (:FIRST
        (let ((val (eval-expr (second expr) interp env)))
          (if (listp val)
              (first val)
              (if (stringp val)
                  (string (char val 0))
                  (interp-error "first expects list or string")))))
       
       (:LAST
        (let ((val (eval-expr (second expr) interp env)))
          (if (listp val)
              (car (last val))
              (if (stringp val)
                  (string (char val (1- (length val))))
                  (interp-error "last expects list or string")))))
       
       (:BUTFIRST
        (let ((val (eval-expr (second expr) interp env)))
          (if (listp val)
              (rest val)
              (if (stringp val)
                  (subseq val 1)
                  (interp-error "butfirst expects list or string")))))
       
       (:BUTLAST
        (let ((val (eval-expr (second expr) interp env)))
          (if (listp val)
              (butlast val)
              (if (stringp val)
                  (subseq val 0 (1- (length val)))
                  (interp-error "butlast expects list or string")))))
       
       (:ITEM
        (let ((index (truncate (eval-expr (second expr) interp env)))
              (val (eval-expr (third expr) interp env)))
          (if (listp val)
              (nth (1- index) val)
              (if (stringp val)
                  (string (char val (1- index)))
                  (interp-error "item expects list or string")))))
       
       (:COUNT
        (let ((val (eval-expr (second expr) interp env)))
          (if (listp val)
              (length val)
              (if (stringp val)
                  (length val)
                  (interp-error "count expects list or string")))))
       
       (:FPUT
        (let ((item (eval-expr (second expr) interp env))
              (lst (eval-expr (third expr) interp env)))
          (cons item lst)))
       
       (:LPUT
        (let ((item (eval-expr (second expr) interp env))
              (lst (eval-expr (third expr) interp env)))
          (append lst (list item))))
       
       ;; Word operations
       (:WORD
        (concatenate 'string
                     (princ-to-string (eval-expr (second expr) interp env))
                     (princ-to-string (eval-expr (third expr) interp env))))
       
       (:SENTENCE
        (let ((a (eval-expr (second expr) interp env))
              (b (eval-expr (third expr) interp env)))
          (append (if (listp a) a (list a))
                  (if (listp b) b (list b)))))
       
       ;; User-defined function call
       (:FUNCALL
        (let* ((name (second expr))
               (args (mapcar (lambda (a) (eval-expr a interp env)) (third expr)))
               (proc (gethash name (interpreter-procedures interp))))
          (unless proc
            (interp-error "Undefined procedure: ~A" name))
          (let ((new-env (make-environment :parent (interpreter-global-env interp))))
            (loop for param in (procedure-params proc)
                  for arg in args
                  do (env-define new-env param arg))
            (handler-case
                (progn
                  (dolist (stmt (procedure-body proc))
                    (eval-stmt stmt interp new-env))
                  nil)  ; No return value
              (procedure-return (c)
                (return-value c))))))
       
       (otherwise
        (interp-error "Unknown expression type: ~A" (first expr)))))
    
    (t (interp-error "Cannot evaluate: ~A" expr))))

(defun truep (val)
  "Check if value is truthy"
  (not (or (null val)
           (equal val "false")
           (equal val 0)
           (equal val ""))))

;;; --- Statement evaluation ---

(defun eval-stmt (stmt interp env)
  "Evaluate a statement"
  (let ((turtle (interpreter-turtle interp)))
    (case (first stmt)
      ;; Movement
      (:FORWARD (turtle-forward turtle (eval-expr (second stmt) interp env)))
      (:BACK (turtle-back turtle (eval-expr (second stmt) interp env)))
      (:RIGHT (turtle-right turtle (eval-expr (second stmt) interp env)))
      (:LEFT (turtle-left turtle (eval-expr (second stmt) interp env)))
      
      ;; Pen control
      (:PENUP (setf (turtle-pen-down turtle) nil))
      (:PENDOWN (setf (turtle-pen-down turtle) t))
      (:PENCOLOR (setf (turtle-pen-color turtle)
                       (eval-expr (second stmt) interp env)))
      (:PENSIZE (setf (turtle-pen-size turtle)
                      (eval-expr (second stmt) interp env)))
      
      ;; Position/heading
      (:HOME (turtle-home turtle))
      (:SETXY (turtle-setxy turtle
                            (eval-expr (second stmt) interp env)
                            (eval-expr (third stmt) interp env)))
      (:SETX (turtle-setx turtle (eval-expr (second stmt) interp env)))
      (:SETY (turtle-sety turtle (eval-expr (second stmt) interp env)))
      (:SETHEADING (turtle-setheading turtle (eval-expr (second stmt) interp env)))
      
      ;; Shapes
      (:CIRCLE (turtle-circle turtle (eval-expr (second stmt) interp env)))
      (:ARC (turtle-arc turtle
                        (eval-expr (second stmt) interp env)
                        (eval-expr (third stmt) interp env)))
      
      ;; Screen
      (:CLEARSCREEN (turtle-clearscreen turtle))
      (:HIDETURTLE (setf (turtle-visible turtle) nil))
      (:SHOWTURTLE (setf (turtle-visible turtle) t))
      
      ;; Control structures
      (:REPEAT
       (let ((count (truncate (eval-expr (second stmt) interp env)))
             (body (third stmt)))
         (dotimes (i count)
           (dolist (s body)
             (eval-stmt s interp env)))))
      
      (:WHILE
       (let ((condition (second stmt))
             (body (third stmt)))
         (loop while (truep (eval-expr condition interp env))
               do (dolist (s body)
                    (eval-stmt s interp env)))))
      
      (:FOR
       (let ((var (second stmt))
             (start (eval-expr (third stmt) interp env))
             (end (eval-expr (fourth stmt) interp env))
             (step (eval-expr (fifth stmt) interp env))
             (body (sixth stmt)))
         (let ((new-env (make-environment :parent env)))
           (if (> step 0)
               (loop for i from start to end by step
                     do (env-define new-env var i)
                        (dolist (s body)
                          (eval-stmt s interp new-env)))
               (loop for i from start downto end by (- step)
                     do (env-define new-env var i)
                        (dolist (s body)
                          (eval-stmt s interp new-env)))))))
      
      (:IF
       (when (truep (eval-expr (second stmt) interp env))
         (dolist (s (third stmt))
           (eval-stmt s interp env))))
      
      (:IFELSE
       (if (truep (eval-expr (second stmt) interp env))
           (dolist (s (third stmt))
             (eval-stmt s interp env))
           (dolist (s (fourth stmt))
             (eval-stmt s interp env))))
      
      ;; Procedure definition
      (:DEFINE
       (setf (gethash (second stmt) (interpreter-procedures interp))
             (make-procedure :name (second stmt)
                             :params (third stmt)
                             :body (fourth stmt))))
      
      ;; Stop (exit procedure)
      (:STOP
       (signal 'procedure-return :value nil))
      
      ;; Output (return value)
      (:OUTPUT
       (signal 'procedure-return :value (eval-expr (second stmt) interp env)))
      
      ;; Variables
      (:MAKE
       (env-set env (second stmt) (eval-expr (third stmt) interp env)))
      
      (:LOCAL
       (env-define env (second stmt) nil))
      
      ;; I/O
      (:PRINT
       (let ((val (eval-expr (second stmt) interp env)))
         (push (format nil "~A" val) (interpreter-output-buffer interp))
         (format t "~A~%" val)))
      
      (:TYPE
       (let ((val (eval-expr (second stmt) interp env)))
         (push (format nil "~A" val) (interpreter-output-buffer interp))
         (format t "~A" val)))
      
      (:SHOW
       (let ((val (eval-expr (second stmt) interp env)))
         (push (format nil "~S" val) (interpreter-output-buffer interp))
         (format t "~S~%" val)))
      
      ;; Procedure call
      (:CALL
       (let* ((name (second stmt))
              (args (mapcar (lambda (a) (eval-expr a interp env)) (third stmt)))
              (proc (gethash name (interpreter-procedures interp))))
         (unless proc
           (interp-error "Undefined procedure: ~A" name))
         (let ((new-env (make-environment :parent (interpreter-global-env interp))))
           (when (/= (length args) (length (procedure-params proc)))
             (interp-error "Procedure ~A expects ~A arguments, got ~A"
                           name (length (procedure-params proc)) (length args)))
           (loop for param in (procedure-params proc)
                 for arg in args
                 do (env-define new-env param arg))
           (handler-case
               (dolist (s (procedure-body proc))
                 (eval-stmt s interp new-env))
             (procedure-return (c)
               (declare (ignore c)))))))
      
      (otherwise
       (interp-error "Unknown statement: ~A" (first stmt))))))

(defun eval-block-as-expr (block interp env)
  "Evaluate a block and return the last expression's value"
  (let ((result nil))
    (dolist (stmt block)
      (setf result (eval-expr stmt interp env)))
    result))

(defun eval-program (program interp)
  "Evaluate entire program"
  (dolist (stmt program)
    (eval-stmt stmt interp (interpreter-global-env interp))))

;;; ========================================
;;; 9. メイン実行関数
;;; ========================================

(defun run (source)
  "Parse and execute source code"
  (let ((interp (make-interpreter)))
    (eval-program (parse source) interp)
    interp))

;;; ========================================
;;; 10. SVG出力
;;; ========================================

(defun svg-header (width height)
  (format nil "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<svg xmlns=\"http://www.w3.org/2000/svg\" 
     width=\"~A\" height=\"~A\" 
     viewBox=\"0 0 ~A ~A\">
  <rect width=\"100%\" height=\"100%\" fill=\"white\"/>
  <g transform=\"translate(~A, ~A) scale(1, -1)\">"
          width height width height (/ width 2) (/ height 2)))

(defun svg-footer ()
  "  </g>
</svg>")

(defun line-to-svg (line)
  (format nil "    <line x1=\"~,2F\" y1=\"~,2F\" x2=\"~,2F\" y2=\"~,2F\" stroke=\"~A\" stroke-width=\"~A\"/>"
          (normalize-zero (line-segment-x1 line))
          (normalize-zero (line-segment-y1 line))
          (normalize-zero (line-segment-x2 line))
          (normalize-zero (line-segment-y2 line))
          (line-segment-color line)
          (line-segment-size line)))

(defun turtle-to-svg (turtle &key (width 400) (height 400))
  (with-output-to-string (out)
    (write-string (svg-header width height) out)
    (terpri out)
    (dolist (line (reverse (turtle-lines turtle)))
      (write-string (line-to-svg line) out)
      (terpri out))
    (write-string (svg-footer) out)))

(defun save-svg (turtle filename &key (width 400) (height 400))
  (with-open-file (out filename :direction :output :if-exists :supersede
                                :external-format :utf-8)
    (write-string (turtle-to-svg turtle :width width :height height) out))
  (format t "SVG saved: ~A~%" filename))

(defun run-and-save (source filename &key (width 400) (height 400))
  (let ((interp (run source)))
    (save-svg (interpreter-turtle interp) filename :width width :height height)
    interp))

;;; ========================================
;;; 11. デモプログラム
;;; ========================================

(defun demo-basic ()
  "Basic shapes demo"
  (run-and-save "
; 正方形
repeat 4 [forward 100 right 90]
" "demo-basic.svg"))

(defun demo-polygon ()
  "Polygon demo with arithmetic"
  (run-and-save "
; 正多角形を描く手続き
to polygon :sides :size
  repeat :sides [
    forward :size
    right 360 / :sides
  ]
end

; 三角形
polygon 3 80

; 移動
penup forward 150 pendown

; 五角形
polygon 5 60

; 移動
penup right 90 forward 150 left 90 pendown

; 八角形
polygon 8 40
" "demo-polygon.svg" :width 500 :height 400))

(defun demo-star ()
  "Star demo"
  (run-and-save "
to star :size :points
  repeat :points [
    forward :size
    right 180 - 180 / :points
  ]
end

star 100 5
penup right 90 forward 200 left 90 pendown
star 80 7
" "demo-star.svg" :width 500 :height 300))

(defun demo-spiral ()
  "Spiral demo with variables"
  (run-and-save "
to spiral :size :angle :increment :count
  repeat :count [
    forward :size
    right :angle
    make \"size :size + :increment
  ]
end

spiral 2 91 2 100
" "demo-spiral.svg" :width 600 :height 600))

(defun demo-colors ()
  "Color demo"
  (run-and-save "
to colorwheel :size
  pencolor \"red
  repeat 60 [forward :size right 6]
  pencolor \"orange
  repeat 60 [forward :size right 6]
  pencolor \"yellow
  repeat 60 [forward :size right 6]
  pencolor \"green
  repeat 60 [forward :size right 6]
  pencolor \"blue
  repeat 60 [forward :size right 6]
  pencolor \"purple
  repeat 60 [forward :size right 6]
end

colorwheel 5
" "demo-colors.svg" :width 400 :height 400))

(defun demo-tree ()
  "Recursive tree demo"
  (run-and-save "
to tree :size :depth
  if :depth = 0 [stop]
  forward :size
  left 30
  tree :size * 0.7 :depth - 1
  right 60
  tree :size * 0.7 :depth - 1
  left 30
  back :size
end

penup back 100 pendown
tree 80 7
" "demo-tree.svg" :width 500 :height 500))

(defun demo-koch ()
  "Koch snowflake demo"
  (run-and-save "
to koch :size :depth
  if :depth = 0 [forward :size stop]
  koch :size / 3 :depth - 1
  left 60
  koch :size / 3 :depth - 1
  right 120
  koch :size / 3 :depth - 1
  left 60
  koch :size / 3 :depth - 1
end

to snowflake :size :depth
  repeat 3 [
    koch :size :depth
    right 120
  ]
end

penup back 80 right 90 forward 150 left 90 pendown
snowflake 300 4
" "demo-koch.svg" :width 600 :height 600))

(defun demo-sierpinski ()
  "Sierpinski triangle demo"
  (run-and-save "
to sierpinski :size :depth
  if :depth = 0 [
    repeat 3 [forward :size right 120]
    stop
  ]
  sierpinski :size / 2 :depth - 1
  forward :size / 2
  sierpinski :size / 2 :depth - 1
  back :size / 2
  left 60
  forward :size / 2
  right 60
  sierpinski :size / 2 :depth - 1
  left 60
  back :size / 2
  right 60
end

penup back 150 left 90 forward 180 right 90 pendown
sierpinski 350 5
" "demo-sierpinski.svg" :width 500 :height 500))

(defun demo-flower ()
  "Flower pattern demo"
  (run-and-save "
to petal :size
  repeat 60 [
    forward :size
    right 3
  ]
  right 120
  repeat 60 [
    forward :size
    right 3
  ]
end

to flower :size :petals
  repeat :petals [
    petal :size
    right 360 / :petals
  ]
end

pencolor \"crimson
flower 2 12
" "demo-flower.svg" :width 400 :height 400))

(defun demo-for-loop ()
  "For loop demo"
  (run-and-save "
; Concentric squares using for loop
for \"i 1 10 [
  repeat 4 [
    forward :i * 20
    right 90
  ]
  penup home pendown
  right :i * 9
]
" "demo-for.svg" :width 500 :height 500))

(defun demo-circles ()
  "Circle and arc demo"
  (run-and-save "
; Draw circles of different sizes
circle 30
penup forward 80 pendown
circle 50
penup forward 100 pendown
circle 70

; Draw arcs
penup home right 90 forward 150 left 90 pendown
arc 180 40
penup forward 50 pendown
arc 90 60
" "demo-circles.svg" :width 500 :height 400))

(defun run-all-demos ()
  "Run all demo programs"
  (format t "~%=== Running all demos ===~%~%")
  (demo-basic)
  (demo-polygon)
  (demo-star)
  (demo-spiral)
  (demo-colors)
  (demo-tree)
  (demo-koch)
  (demo-sierpinski)
  (demo-flower)
  (demo-for-loop)
  (demo-circles)
  (format t "~%=== All demos completed ===~%"))

;;; ========================================
;;; 12. テスト
;;; ========================================

(defun test-arithmetic ()
  "Test arithmetic expressions"
  (format t "~%=== Arithmetic Tests ===~%")
  (let ((interp (run "
make \"a 10
make \"b 3
make \"sum :a + :b
make \"diff :a - :b
make \"prod :a * :b
make \"quot :a / :b
make \"mod :a % :b
print :sum
print :diff
print :prod
print :quot
print :mod
")))
    (format t "Output: ~A~%" (reverse (interpreter-output-buffer interp)))))

(defun test-comparison ()
  "Test comparison operators"
  (format t "~%=== Comparison Tests ===~%")
  (let ((interp (run "
make \"x 5
if :x < 10 [print \"less]
if :x > 3 [print \"greater]
if :x = 5 [print \"equal]
ifelse :x < 0 [print \"negative] [print \"positive]
")))
    (format t "Output: ~A~%" (reverse (interpreter-output-buffer interp)))))

(defun test-recursion ()
  "Test recursion"
  (format t "~%=== Recursion Tests ===~%")
  (let ((interp (run "
to factorial :n
  if :n <= 1 [output 1]
  output :n * factorial :n - 1
end

print factorial 5
print factorial 10
")))
    (format t "Output: ~A~%" (reverse (interpreter-output-buffer interp)))))

(defun test-lists ()
  "Test list operations"
  (format t "~%=== List Tests ===~%")
  (let ((interp (run "
make \"colors [red green blue]
print first :colors
print last :colors
print butfirst :colors
print count :colors
print item 2 :colors
print fput \"yellow :colors
print lput \"purple :colors
")))
    (format t "Output: ~A~%" (reverse (interpreter-output-buffer interp)))))

(defun test-while ()
  "Test while loop"
  (format t "~%=== While Loop Tests ===~%")
  (let ((interp (run "
make \"i 1
while [:i <= 5] [
  print :i
  make \"i :i + 1
]
")))
    (format t "Output: ~A~%" (reverse (interpreter-output-buffer interp)))))

(defun test-for ()
  "Test for loop"
  (format t "~%=== For Loop Tests ===~%")
  (let ((interp (run "
for \"i 1 5 [
  print :i * :i
]
")))
    (format t "Output: ~A~%" (reverse (interpreter-output-buffer interp)))))

(defun test-all ()
  "Run all tests"
  (format t "~%========================================~%")
  (format t "Running All Tests~%")
  (format t "========================================~%")
  (test-arithmetic)
  (test-comparison)
  (test-recursion)
  (test-lists)
  (test-while)
  (test-for)
  (format t "~%========================================~%")
  (format t "All Tests Completed~%")
  (format t "========================================~%"))

;;; ========================================
;;; 使用方法
;;; ========================================
;;; (load "turtle-lang-full.lisp")
;;; (test-all)
;;; (run-all-demos)
;;; (run-and-save "repeat 4 [fd 100 rt 90]" "output.svg")
