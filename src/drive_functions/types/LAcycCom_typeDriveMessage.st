NAMESPACE Simatic.Ax.LAcycCom.Procedural
  TYPE
    /// Describes the values of a drive message used by LAcycCom_ReadDriveMessagesDateTime and LAcycCom_ReadDriveMessagesOperatingHours
    LAcycCom_typeDriveMessage : STRUCT
      messageType : LAcycCom_DriveMessageType;   /// type of drive message
      code : UINT;   /// code of the drive message (see respective drive function manual for further details)
      info : UDINT;  /// info of the drive message (see respective drive function manual for further details)
      comeDateAndTime : LDATE_AND_TIME;   /// timestamp of incoming message
    END_STRUCT;
  END_TYPE
END_NAMESPACE