NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE
    /// Contains the message types that are retrieved from the drive via LAcycCom_ReadDriveMessagesDateTime and LAcycCom_ReadDriveMessagesOperatingHours
    LAcycCom_DriveMessageType : SINT (
      ALARM := SINT#1,   /// type alarm
      FAULT := SINT#2,   /// type fault
      SI_MESSAGE := SINT#3   /// type SI message
    ) := ALARM;
  END_TYPE
END_NAMESPACE