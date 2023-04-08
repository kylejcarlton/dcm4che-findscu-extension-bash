#!/bin/bash
#Persistent Environment Variables: ~/.bash_profile {DCM4CHE_PATH, OPTIMIZE_AET, OPTIMIZE_IP, OPTIMIZE_Port, PACS_#_AET, PACS_#_IP, PACS_#_Port, ...}
SELECTED_DATE="$1"
RESULTS_PATH=~/DICOM_QR
PACS_AET=$PACS_1_AET
PACS_IP=$PACS_1_IP
PACS_Port=$PACS_1_Port
#C-FIND and C-MOVE operations
FINDSCU="$DCM4CHE_PATH/bin/findscu --connect $PACS_AET@$PACS_IP:$PACS_Port --bind $OPTIMIZE_AET@$OPTIMIZE_IP:$OPTIMIZE_Port --out-dir $RESULTS_PATH/CFIND_Results"
MOVESCU="$DCM4CHE_PATH/bin/movescu --connect $PACS_AET@$PACS_IP:$PACS_Port --bind $OPTIMIZE_AET@$OPTIMIZE_IP:$OPTIMIZE_Port --dest $OPTIMIZE_AET"

# Require Date in correct format or exit
if [[ "$SELECTED_DATE" = "" ]]
  then
    echo "1st argument must be date in format YYYYMMDD or range YYYYMMDD-YYYYMMDD ."
    echo "Exiting. Run script with required arguments."
    exit 1
fi

# Clear previous results
rm -r $RESULTS_PATH/*

# Submit C-FIND Request to PACS for all studies over date range
$FINDSCU --datetime -m 00080020=$SELECTED_DATE -r StudyInstanceUID  -X

# Print all Study Instance UIDs from C-FIND results in a single file seperated by line breaks
for i in $RESULTS_PATH/CFIND_Results/*.dcm; do xmllint --xpath "string(//DicomAttribute[@keyword='StudyInstanceUID'])" $i >> $RESULTS_PATH/StudyIUIDs && printf "\n" >> $RESULTS_PATH/StudyIUIDs; done

# Set counter to  0 
counter=0

# Collect (C-MOVE) single instance from each study returned in C-FIND request above to parse DICOM tags defined in keys[] and tags[] from instance 
while read line; do
  
  # Print counter to Study Details
  printf "$counter|" >> $RESULTS_PATH/StudyDetails

  # Series Level C-FIND request based on Study Instance UID to return Modality and Study Instance UID of nth Study
  $FINDSCU -L SERIES -m 0020000D=$line -r 0020000D -r 00080060 -X
  
  # keys[] acts as counter and defines DICOM fields to parse from C-FIND results returned above
  # Prints DICOM tags defined in keys[] to Study Details
  keys=(StudyInstanceUID Modality)
  for i in "${keys[@]}" 
  do
  printf $i":" >> $RESULTS_PATH/StudyDetails && xmllint --xpath "string(//DicomAttribute[@keyword='"$i"'])" $RESULTS_PATH/CFIND_Results/001.dcm >> $RESULTS_PATH/StudyDetails && printf "|" >> $RESULTS_PATH/StudyDetails
  done

  # Image Level C-FIND request of nth Study Instance UID to return SOP Instance UID and Series Instance UID
  $FINDSCU -L IMAGE -m 0020000D=$line -r 00080018 -r 0020000E  -X
  # Take first instance of study (this could be improved by creating logic to take middle slice of study)
  SERIESIUID=$(xmllint --xpath "string(//DicomAttribute[@keyword='SeriesInstanceUID'])" $RESULTS_PATH/CFIND_Results/001.dcm)
  SOPIUID=$(xmllint --xpath "string(//DicomAttribute[@keyword='SOPInstanceUID'])" $RESULTS_PATH/CFIND_Results/001.dcm)
  # C-MOVE request for first instance of nth study
  $MOVESCU -L IMAGE -m StudyInstanceUID=$line -m SeriesInstanceUID=$SERIESIUID -m SOPInstanceUID=$SOPIUID
  # sleep to ensure the instances complete transfer from PACS to OPSS over hospital network
  sleep 5s
  # tags[] acts as counter and defines DICOM fields to parse from single instance returned in C-MOVE request above
  tags=(Manufacturer ManufacturerModelName StationName InstitutionName)
  # Prints DICOM tag values defined in tags[] to Study Details
  for j in "${tags[@]}"
  do
  printf $j":" >> $RESULTS_PATH/StudyDetails
  $DCM4CHE_PATH/bin/dcmdump Upload/$SOPIUID | grep -Po "\[(.*?)\](?= \b$j\b)" | tr '\n' '\0' | sed 's/[][]//g' >> $RESULTS_PATH/StudyDetails && printf "|" >> $RESULTS_PATH/StudyDetails
  done
  # Print new line to Study Details and increments counter 
  printf "\n" >> $RESULTS_PATH/StudyDetails
  counter=$((counter+1))
done < $RESULTS_PATH/StudyIUIDs

# Output full results to terminal
cat $RESULTS_PATH/StudyDetails
