A small utility that will read in RABOBANK CSV account details and converts it into MT940 format (also called SWI-format).
I was inspired by a generic version by Bruno Brueckmann (2018) but that did not support dutch RABObank. 

Handy for people who have a personal RABO account and still need this format.

Instructiopns for usage:
- download Transactions for the entire year in CSAV-format.
    - For those who don't know how:
     - Go into your broweser, log into RABO-website, 
     - select account
     - click 3 dots
     - downloadm transactions
     - select CSV-format.
- execute script with two arguments: Convert.._SWI.sh arg1 arg2
    - arg1 input file (the one just downloaded)
    - arg2 output file (the swi-file.)
    
