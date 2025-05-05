#!/bin/bash
#M convert Rabobank-CSV-File to (Rabobank) MT940 format 
# Original idea: Bruno Brueckmann 2018, adapted/rewritten for use of Rabobank-=CSV by TonO
   export LC_NUMERIC="de_DE.UTF-8"

QuotesUsed='"'
Sep=";"
DefinedFields=("IBAN/BBAN" "Munt" "BIC" "Volgnr" "Datum" "Rentedatum" "Bedrag" "Saldo na trn" "Tegenrekening IBAN/BBAN" "Naam tegenpartij" "Naam uiteindelijke partij" "Naam initi\x82rende partij" "BIC tegenpartij" "Code" "Batch ID" "Transactiereferentie" "Machtigingskenmerk" "Incassant ID" "Betalingskenmerk" "Omschrijving-1" "Omschrijving-2" "Omschrijving-3" "Reden retour" "Oorspr bedrag" "Oorspr munt" "Koers")
declare -a MyFields
OutFile=$2
IBAN=0
Munt=1
BIC=2
VolgrNr=3
Datum=4
Rentedatum=5
Bedrag=6
Saldonatrn=7
TegenrekeningIban=8
NaamTegenpartij=9
Naamuiteindelijkepartij=10
Naaminitierendepartij=11
BICtegenpartij=12
Code=13
BatchID=14
Transactiereferentie=15
Machtigingskenmerk=16
IncassantID=17
Betalingskenmerk=18
Omschrijving1=19
Omschrijving2=20
Omschrijving3=21
Redenretour=22
Oorsprbedrag=23
Oorsprmunt=24
Koers=25

declare -a MyValues
Afschriftnr=22000
LastRekening=
LastDatum=
LastSaldo=63614,28
Saldo=63614,28
Converted_Code=0
FirstWrite=1
#######################################################################
LoadHeaderFields()
{
IFS="$Sep"
# Input string to be split
# Use the read command to split the input string
n=0
read -ra array <<< "$@"
# Iterate over the elements of the array

   ThisColumn=-1
      for element in "${array[@]}"
      do
         ThisColumn=$(( ThisColumn + 1 ))
         if [[ $QuotesUsed == '"' ]] 
         then
            ThisElement=$(echo "$element" | awk -F'"' '{print $2}')
         else
            ThisElement=$(echo "$element" | awk -F"'" '{print $2}')
         fi
         Found=0
         for i in ${!DefinedFields[@]} 
         do 
            if [[ "${DefinedFields[$i]}" == "$ThisElement" ]]
            then
               MyFields[$i]=$ThisColumn
               Found=1
               break
            fi
         done
         if [[ $Found -eq 0 ]]   # Field Not found
         then  # but first check, field "Naam initierende partij" has diacritics that spoils comparison; check this entry manually
            if [[ "${ThisElement:0:10}" == "Naam initi" && "${ThisElement:11:12}" == "rende partij" ]]
            then  
               MyFields[$Naaminitierendepartij]=$ThisColumn
            else
               echo "Input field $ThisElement is unknown; skipping that field"
            fi
         fi
      done

}

ReadHeader() 
{
   # first check to see if we use (double) quotes around each field
   # Then determine separator; it i CSV, but the ";" character is used in Europe a lot as seperator
   # Then read all columns and associate each fieldname with its column position
   # last, build an array of fieldnames and their column position 
   LINE=$@
   QuotesUsed=${LINE:0:1}
   if [[ $QuotesUsed == '"' ]]
      then
      Pos=$(echo ${LINE:1:999} | grep -ob '\"')
   else
      Pos=$(echo ${LINE:1:999} | grep -ob "'")
   fi

   Pos=$(echo ${Pos}|awk ' BEGIN { FS=":" } {print $1}')
   Pos=$((Pos+2))
   Sep=${LINE:$Pos:1}
   LoadHeaderFields $@

}

Write_Outfile()
{
   if [[ "$FirstWrite" == "1" ]]
   then
      retval=$(rm "$OutFile" > /dev/null)
      FirstWrite=0
      Write_Outfile ":940:"  # write file header
   fi       
   OutString="$@"
   while [ ${#OutString} -gt 0 ]
   do
      Thisrec=${OutString:0:70}
      echo "$Thisrec" >>$OutFile 
      if [[ ${#OutString} -gt 70 ]]
      then
         OutString=${OutString:70:9999}
      else
         OutString=""
      fi 
   done 

}

Convert_Code()
{
   # Code EI = Incasso          = 056 / NDDT 
# code CB = Overboeking      = 541 / NTRF
# code GA = geldautomaat     = 023 / NMSC
# code ID = IDEAL betaling D = 102 / NTRF
# code ID = IDEAL ontvangstC = 100 / NTRF
# code DB = Kosten RABO      = 1029 / NTRF
# code BG = Online bankieren = 547 / NTRF
# code BA = Betaalautomaat   = 030 / NTRF
# code BC = Betaalautomaat   = 002 / NTRF
# code TB = Spaarrekening  D = 501 / 699

# :61:190314D000000000011,00N030NONREF//5HM43940714203
# 0000000000
# :86:/TRCD/030/BENM//NAME/POOC UTRECHT/REMI/Betaalautomaat 16:35 pasnr
#. 056


   case $(echo "${MyValues[$Code]}"  | tr a-z A-Z)  in 
     EI) Converted_Code="056"
     ;;
     CB) Converted_Code="541"
     ;;
     ID) if [[ "${MyValues[$Bedrag]:0:1}" == "-" ]]
         then
             Converted_Code="102"
         else
             Converted_Code="100"
         fi
     ;;
     DB) Converted_Code="1029" 
     ;;
     BA) Converted_Code="547"
     ;;
     BC) Converted_Code="030"
     ;;
     BG) Converted_Code="547"
     ;;
     GA) Converted_Code="023"
     ;;
     TB) 
      if [[ "${MyValues[$Bedrag]:0:1}" == "-" ]]
         then
             Converted_Code="501"
         else
             Converted_Code="699"
         fi
     ;;
     *) echo "Unknown code ${MyValues[$Code]}"
         Converted_Code="???"
   esac
   
}

Write_20() # Afschrift
{   
    Write_Outfile ":20:940S${Converted_Datum}"  
    Saldo="$LastSaldo"

}

Write_25()  # Rekening 9+ munt
{
    Write_Outfile ":25:${MyValues[$IBAN]} ${MyValues[$Munt]}"  

}

Write_28() # Afschriftnummer / volgnummer
{
   Afschriftnr="${Converted_Datum:0:2}${Afschriftnr:2:3}"
    Write_Outfile ":28C:${Afschriftnr}"   

}

Write_60F() # vorig boeksaldo (beginsaldo afschrift) / Opening balance
{   #echo "60f Saldonatrn: " ${MyValues[$Saldonatrn]}  "Bedrag: "  ${MyValues[$Bedrag]}
   #echo ""                                              

   # Bash will normally treat variables with nubers as integers, so we need to use the bc utlity to do floating point calculations
   #                                                     # First we prepare our variables for use by bc....
   ThisSaldoNaTrn=${MyValues[$Saldonatrn]}
   ThisSaldoNaTrn=$(echo $ThisSaldoNaTrn | tr  ',' '\.') # change decimal comma into decimal point (as bc only works with Decimal Point)
   ThisBedrag=${MyValues[$Bedrag]}
   ThisBedrag=$(echo $ThisBedrag | tr  ',' '\.')
   if [[ ${ThisSaldoNaTrn:0:1} == "+" ]]                 # bc errors out on leading "+" signs, so remove them 
      then
      ThisSaldoNaTrn=${ThisSaldoNaTrn:1:99}
   fi
   if [[ ${ThisBedrag:0:1} == "+" ]]                     # ditto
      then
      ThisBedrag=${ThisBedrag:1:99}
   fi
   Saldo=$(echo "$ThisSaldoNaTrn - $ThisBedrag" |bc -l)  # Finally we can calculate: simple subtract amount of txn from new saldo gives current saldo
   Saldo=$(echo $Saldo | tr  '\.' ',')         # and convert decimal point back to comma

   LC_NUMERIC="de_DE.UTF8" SaldoBeforeTXN=$(printf "%015.2f" "$Saldo")
   if [[ "${Saldo:0:1}" == "-" ]]
   then
      DC="D"
      Saldo=${Saldo:1:99}                                # Strip of minus sign as it will be reflected in the DC-code
   else  
      DC="C"
   fi   
   Write_Outfile ":60F:${DC}${Converted_Datum}${MyValues[$Munt]}$SaldoBeforeTXN"  

}

Write_61()  # Transactie
{
   if [[ "${MyValues[$Bedrag]:0:1}" == "-" ]]
   then
      DC="D"
   else  
      DC="C"
   fi 
   MyBedrag=$(printf '%015.2f' "${MyValues[${Bedrag}]:1:99}")
   Convert_Code
   Write_Outfile ":61:${Converted_Datum}${DC}${MyBedrag}N${Converted_Code}//RE00000000-10001" 
   Write_Outfile "${MyValues[${TegenrekeningIban}]}"  

}

Write_62F() #Huidig Boeksaldo
{
   if [[ "${LastSaldo:0:1}" == "-" ]]
   then
      DC="D"
   else  
      DC="C"
   fi 
   MyBedrag=$(LC_NUMERIC=C printf '%015.2f' "${LastSaldo:1:99}")
   Write_Outfile ":62F:${DC}${Converted_Datum}${MyValues[$Munt]}${MyBedrag}"  

}

Write_86() #Omschrijving transactie 
{
   Convert_Code
   The86Codes="${Converted_Code}"

   AddThis="/REMI/"
   if [[ ${#MyValues[$NaamTegenpartij]} -gt 0  ]]
   then
      The86Codes="${The86Codes}/BENM//NAME/${MyValues[$NaamTegenpartij]}"
   fi
   if [[ ${#MyValues[$Omschrijving1]} -gt 0  ]]
   then
      The86Codes="${The86Codes}${AddThis}${MyValues[$Omschrijving1]}"
      AddThis=""
   fi
   if [[ ${#MyValues[$Omschrijving2]} -gt 0  ]]
   then
      The86Codes="${The86Codes}${AddThis}${MyValues[$Omschrijving2]}"
      AddThis=""
   fi
   if [[ ${#MyValues[$Omschrijving3]} -gt 0  ]]
   then
      The86Codes="${The86Codes}${AddThis}${MyValues[$Omschrijving3]}"
      AddThis=""
   fi
   Write_Outfile ":86:/TRCD/${The86Codes}"  
   LastSaldo="${MyValues[$Saldonatrn]}"

}

Write_Afschrift()
{
      Afschriftnr=$((Afschriftnr+1))
      Saldo=$LastSaldo
      if [[ ${#LastRekening} -gt 0 ]] # did we write records already?
      then
            Write_62F
      fi
      Write_20
      Write_25
      Write_28
      Write_60F

}

WriteOut()
{
   Converted_Datum="${MyValues[$Datum]:2:2}${MyValues[$Datum]:5:2}${MyValues[$Datum]:8:2}"

   if [[  "${MyValues[$IBAN]}" != "$LastRekening"  ]] #||  "${Converted_Datum}" -ne "$LastDatum"  ]]
      then
         #echo "Iban is different from previous one, writing afschrift"
         Write_Afschrift
         LastSaldo=0
   fi
   Write_61
   Write_86
   LastRekening=${MyValues[$IBAN]}
   LastDatum=${MyValues[$Datum]}

}

HandleDetail() 
{
   N=$((N+1))
   IFS=""
   LINE="$1"
   declare -a DetailArray
    #-e "\b\b\b" # erase previous counter

   printf "\b\b\b%03d" $N   
   str=${LINE}
   ThisColumn=-1
   GoOn=1
   while [ $GoOn -eq 1 ] 
   do
      if [[ ${#str} -gt 0 ]]
      then 
         ThisElement=$(echo "$str" | awk -F'"' '{print $2}')  
         ThisColumn=$((ThisColumn+1))
         DetailArray[$ThisColumn]="$ThisElement"
         len=${#ThisElement}
         len=$((len+3))
         str=${str:$len:9999}
      else
         GoOn=0
      fi
      
   done

# Iterate over the elements of the array

   for MyField in "${!MyFields[@]}"
   do
      Column=${MyFields[$MyField]}         
      MyValues[$MyField]=${DetailArray[$Column]}
   done
   WriteOut 
   

}
if [ -z $1 ]; then
 echo "Error No Input"
 echo "calling: Convert_Rabo_CSV_To_MT940.sh sourcefile destfile"
 exit 
fi
if [ -z $OutFile ]; then
 echo "Error No Input"
 echo "calling: Convert_Rabo_CSV_To_MT940.sh sourcefile destfile"
 exit 
fi

LC_NUMERIC="nl_NL.UTF-8"
n=0  #record -counter

while IFS='' read -r LINE
     do 
      if [[ ${n} -eq 0 ]]
         then
            ReadHeader $LINE
            printf "Processing record nr. 000" 

      else
         HandleDetail "${LINE}"
      fi 


     n=`echo $n+1|bc`
done < $1
#Converted_Datum="${Converted_Datum:0:2}1231"
#Write_Afschrift
Write_62F

printf "\n\nInput converted to MT940S-format and written to %s" "$OutFile"
exit