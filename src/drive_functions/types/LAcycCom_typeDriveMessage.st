NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE
        /// Describes the values of a drive message used by LAcycCom_ReadDriveMessagesDateTime and LAcycCom_ReadDriveMessagesOperatingHours
        typeDriveMessage : STRUCT
            /// Type of drive message (e.g., Fault, Alarm, or Maintenance Requirement)
            messageType : DriveMessageType;
            /// Code of the drive message (see respective drive function manual for details)
            code : UINT;
            /// Info of the drive message (additional diagnostic data/sub-codes)
            info : UDINT;
            /// Timestamp of when the message occurred
            comeDateAndTime : LDATE_AND_TIME;
        END_STRUCT;
    END_TYPE
END_NAMESPACE