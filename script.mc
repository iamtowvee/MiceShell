~load:mice@0.1.0
#^enc 65001
^outln HELLO!
^outln Press "Y" if you want download file
^takes (press.Y and press.L_SHIFT) ? (dwn https://raw.githubusercontent.com/iamtowvee/iamtowvee/refs/heads/main/tests/0x0000.txt : 0.txt) : (outln OK.)
^outln Done.