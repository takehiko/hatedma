;; 行頭から http://d.hatena.ne.jp/hatenausername/ を探し，見つかれば，
;; その後ろの値（年月日とutime）をもとに ~/.hatedma/data の
;; テキストファイルを開く
(defun find-file-hatedma ()
  "Open ~/.hatedma/data/yyyy/mm/dd_utime.txt file by URL"
  (interactive)
  (beginning-of-line)
  (save-excursion
    (let* ((pos (search-forward "http://d.hatena.ne.jp/hatenausername/" (point-max) t)))
      (if (not (eq pos nil))
          (let* ((base "~/.hatedma/data/")
                 (year (buffer-substring (point) (+ (point) 4)))
                 (mon (buffer-substring (+ (point) 4) (+ (point) 6)))
                 (day (buffer-substring (+ (point) 6) (+ (point) 8)))
                 (utime (buffer-substring (+ (point) 9) (+ (point) 19)))
                 (filename (concat base year "/" mon "/" day "_" utime ".txt")))
            (find-file filename)
            (message filename))))))
