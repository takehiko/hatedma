;; 行頭から http://d.hatena.ne.jp/はてなユーザー名/ を探し，見つかれば，
;; その後ろの値（年月日とutime）をもとに ~/.hatedma/はてなユーザー名/data の
;; テキストファイルを開く
(defun find-file-hatedma ()
  "Open ~/.hatedma/USER/data/YYYY/MM/DD_UTIME.txt file by URL"
  (interactive)
  (save-excursion
    (let* ((pos (search-forward "http://d.hatena.ne.jp/" (point-max) t)))
      (if (not (eq pos nil))
          (progn
            (forward-char)
            (let* ((pos2 (search-forward "/" (point-max) t)))
              (if (not (eq pos2 nil))
                  (let* ((base "~/.hatedma/")
                         (name (buffer-substring pos (- (point) 1)))
                         (year (buffer-substring (point) (+ (point) 4)))
                         (mon (buffer-substring (+ (point) 4) (+ (point) 6)))
                         (day (buffer-substring (+ (point) 6) (+ (point) 8)))
                         (utime (buffer-substring (+ (point) 9) (+ (point) 19)))
                         (filename (concat base name "/data/" year "/" mon "/" day "_" utime ".txt")))
                    (find-file filename)
                    (message filename)))))))))
