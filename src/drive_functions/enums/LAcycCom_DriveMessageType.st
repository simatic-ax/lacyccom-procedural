NAMESPACE Simatic.Ax.LAcycCom.Procedural
    TYPE
        /// Contains the message types that are retrieved from the drive via LAcycCom_ReadDriveMessagesDateTime and LAcycCom_ReadDriveMessagesOperatingHours
        DriveMessageType : SINT (
            /// Type alarm
            ALARM := SINT#1,
            /// Type fault
            FAULT := SINT#2,
            /// Type SI message
            SI_MESSAGE := SINT#3
        ) := ALARM;
    END_TYPE
END_NAMESPACE