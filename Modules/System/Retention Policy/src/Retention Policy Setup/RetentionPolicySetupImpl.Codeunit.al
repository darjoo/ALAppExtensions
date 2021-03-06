// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------

codeunit 3903 "Retention Policy Setup Impl."
{
    Access = Internal;
    EventSubscriberInstance = Manual;

    var
        ManualSetupNameTxt: Label 'Retention Policies';
        ManualSetupDescriptionTxt: Label 'Set up retention policies for log tables to automatically delete expired records.';
        ManualSetupKeyWordsTxt: Label 'Retention, Delete, Cleanup, Log';
        RetentionPeriodUsedErr: Label 'You cannot delete the retention period %1 because one or more retention policies are using it.', Comment = '%1 = a retention period code';
        RetentionPeriodLockedErr: Label 'You cannot modify the retention period %1 because one or more mandatory retention policies are using it.', Comment = '%1 = a retention period code';
        TableNotAllowedErrorLbl: Label 'Table %1 %2 is not in the list of allowed tables.', Comment = '%1 = table number, %2 = table name';
        FilterPageBuilderCaptionLbl: Label '%1 Filters', Comment = '%1 = Table caption (i.e. Change Log Entry';
        MinExpirationDateErr: Label 'The expiration date for this retention policy must be equal to or before %1.', Comment = '%1 = Date';
        RetentionPolicySetupLineLockedErr: Label 'The retention policy setup for table %1, %2 has mandatory filters that cannot be modified.', Comment = '%1 = table number, %2 = table caption';
        RetenPolAllowedTableFilterMismatchLbl: Label 'The retention policy allow list contains a mismatched filter for table ID %1. Filter table ID is %2', Comment = '%1 = table number, %2 = table number';
        DeleteAllowedInfoLbl: Label 'Allowed deletion of the locked retention policy setup line for table %1, %2.', Comment = '%1 = table number, %2 = table caption';
        DeleteAllowedList: List of [Integer];
        ReadPermissionNotificationLbl: Label 'The number of expired records cannot be calculated because you do not have read permission on table %1, %2.', Comment = '%1 = table number, %2 = table caption';

    procedure SetTableFilterView(var RetentionPolicySetupLine: Record "Retention Policy Setup Line"): Text
    var
        RetenPolFilterPageBuilder: FilterPageBuilder;
        OutStream: OutStream;
        FilterView: Text;
        FilterText: Text;
    begin
        FilterView := GetTableFilterView(RetentionPolicySetupLine);

        RetentionPolicySetupLine.CalcFields("Table Caption");
        RetenPolFilterPageBuilder.AddTable(RetentionPolicySetupLine."Table Caption", RetentionPolicySetupLine."Table ID");

        if FilterView <> '' then
            RetenPolFilterPageBuilder.SetView(RetentionPolicySetupLine."Table Caption", FilterView);

        RetenPolFilterPageBuilder.PageCaption(StrSubstNo(FilterPageBuilderCaptionLbl, RetentionPolicySetupLine."Table Caption"));
        if not RetenPolFilterPageBuilder.RunModal() then
            exit(RetentionPolicySetupLine."Table Filter Text"); // if cancelled, keep previous value

        FilterView := RetenPolFilterPageBuilder.GetView(RetentionPolicySetupLine."Table Caption", false);
        FilterText := ConvertFilterViewToFilterText(FilterView, RetentionPolicySetupLine."Table ID");

        if FilterText <> '' then begin
            RetentionPolicySetupLine."Table Filter".CreateOutStream(OutStream, TextEncoding::UTF8);
            OutStream.Write(FilterView);
        end else
            clear(RetentionPolicySetupLine."Table Filter");

        exit(FilterText);
    end;

    procedure GetTableFilterView(RetentionPolicySetupLine: Record "Retention Policy Setup Line"): Text
    var
        TempRetentionPolicySetupLine: Record "Retention Policy Setup Line" temporary;
        InStream: InStream;
        FilterText: Text;
    begin
        if CalcTableFilterBlob(RetentionPolicySetupLine, TempRetentionPolicySetupLine) then begin
            TempRetentionPolicySetupLine."Table Filter".CreateInStream(InStream, TextEncoding::UTF8);
            InStream.Read(FilterText);
            exit(FilterText);
        end;
    end;

    procedure GetTableFilterText(RetentionPolicySetupLine: Record "Retention Policy Setup Line"): Text
    begin
        exit(ConvertFilterViewToFilterText(GetTableFilterView(RetentionPolicySetupLine), RetentionPolicySetupLine."Table ID"))
    end;

    local procedure ConvertFilterViewToFilterText(FilterView: Text; TableId: Integer): Text
    var
        RecRef: RecordRef;
    begin
        RecRef.Open(TableId);
        RecRef.SetView(FilterView);
        exit(RecRef.GetFilters());
    end;

    local procedure CalcTableFilterBlob(var RetentionPolicySetupLine: Record "Retention Policy Setup Line"; var TempRetentionPolicySetupLine: Record "Retention Policy Setup Line" temporary): Boolean
    begin
        TempRetentionPolicySetupLine."Table Filter" := RetentionPolicySetupLine."Table Filter";
        if not TempRetentionPolicySetupLine."Table Filter".HasValue then
            RetentionPolicySetupLine.CalcFields("Table Filter");
        TempRetentionPolicySetupLine."Table Filter" := RetentionPolicySetupLine."Table Filter";

        exit(TempRetentionPolicySetupLine."Table Filter".HasValue)
    end;

    procedure TableIdLookup(TableId: Integer): Integer
    var
        AllObjWithCaption: Record AllObjWithCaption;
        RetentionPolicySetup: Record "Retention Policy Setup";
        RetenPolAllowedTables: Codeunit "Reten. Pol. Allowed Tables";
    begin
        AllObjWithCaption.FilterGroup := 2;
        AllObjWithCaption.SetRange("Object Type", AllObjWithCaption."Object Type"::Table);
        AllObjWithCaption.SetFilter("Object ID", RetenPolAllowedTables.GetAllowedTables());
        AllObjWithCaption.FilterGroup := 0;

        if RetentionPolicySetup.Get(TableId) then begin
            // lookup on an existing value, show all
            AllObjWithCaption."Object Type" := AllObjWithCaption."Object Type"::Table;
            AllObjWithCaption."Object ID" := TableId
        end else
            // filter out used values
            AllObjWithCaption.SetFilter("Object ID", GetUsedTablesFilter());

        if Page.RunModal(Page::Objects, AllObjWithCaption) = Action::LookupOK then
            TableId := AllObjWithCaption."Object ID";
        exit(TableId);
    end;

    local procedure GetUsedTablesFilter() FilterText: Text
    var
        RetentionPolicySetup: Record "Retention Policy Setup";
        Count: Integer;
    begin
        Count := RetentionPolicySetup.Count();
        if Count = 0 then
            exit('<> 0'); // -> don't set a filter

        RetentionPolicySetup.FindSet();
        FilterText := '<>' + Format(RetentionPolicySetup."Table Id");

        if Count >= 2 then
            repeat
                FilterText += '&<>' + Format(RetentionPolicySetup."Table Id");
            until RetentionPolicySetup.Next() = 0;
    end;

    procedure DateFieldNoLookup(TableId: Integer; FieldNo: Integer): Integer
    var
        SelectedField: Record Field;
        FieldSelection: Codeunit "Field Selection";
    begin
        SelectedField.FilterGroup := 2;
        SelectedField.SetRange(TableNo, TableId);
        SelectedField.SetFilter(Type, '%1|%2', SelectedField.Type::Date, SelectedField.Type::DateTime);
        SelectedField.FilterGroup := 0;
        SelectedField."No." := FieldNo;

        if FieldSelection.Open(SelectedField) then
            FieldNo := SelectedField."No.";

        exit(FieldNo);
    end;

    procedure IsRetentionPolicyEnabled(): Boolean
    var
        RetentionPolicySetup: Record "Retention Policy Setup";
    begin
        RetentionPolicySetup.Setrange(Enabled, true);
        exit(not RetentionPolicySetup.IsEmpty())
    end;

    procedure IsRetentionPolicyEnabled(TableId: Integer): Boolean
    var
        RetentionPolicySetup: Record "Retention Policy Setup";
    begin
        RetentionPolicySetup.Get(TableId);
        exit(RetentionPolicySetup.Enabled)
    end;

    procedure ValidateRetentionPeriod(RetentionPolicySetup: Record "Retention Policy Setup")
    var
        RetentionPeriod: Record "Retention Period";
        RetenPolAllowedTables: Codeunit "Reten. Pol. Allowed Tables";
        RetentionPolicyLog: Codeunit "Retention Policy Log";
        RetentionPeriodInterface: Interface "Retention Period";
        ExpirationDate: Date;
        MinExpirationDate: Date;
    begin
        if RetentionPeriod.Get(RetentionPolicySetup."Retention Period") then begin
            RetentionPeriodInterface := RetentionPeriod."Retention Period";
            ExpirationDate := RetentionPeriodInterface.CalculateExpirationDate(RetentionPeriod);
            MinExpirationDate := RetenPolAllowedTables.CalcMinimumExpirationDate(RetentionPolicySetup."Table Id");
            if ExpirationDate > MinExpirationDate then
                RetentionPolicyLog.LogError(LogCategory(), StrsubstNo(MinExpirationDateErr, MinExpirationDate));
        end;
    end;

    procedure ValidateRetentionPeriod(RetentionPolicySetupLine: Record "Retention Policy Setup Line")
    var
        RetentionPeriod: Record "Retention Period";
        RetenPolAllowedTables: Codeunit "Reten. Pol. Allowed Tables";
        RetentionPolicyLog: Codeunit "Retention Policy Log";
        RetentionPeriodInterface: Interface "Retention Period";
        ExpirationDate: Date;
        MinExpirationDate: Date;
    begin
        if RetentionPeriod.Get(RetentionPolicySetupLine."Retention Period") then begin
            RetentionPeriodInterface := RetentionPeriod."Retention Period";
            ExpirationDate := RetentionPeriodInterface.CalculateExpirationDate(RetentionPeriod);
            MinExpirationDate := RetenPolAllowedTables.CalcMinimumExpirationDate(RetentionPolicySetupLine."Table Id");
            if ExpirationDate > MinExpirationDate then
                RetentionPolicyLog.LogError(LogCategory(), StrsubstNo(MinExpirationDateErr, MinExpirationDate));
        end;
    end;

    procedure LogCategory(): Enum "Retention Policy Log Category"
    var
        RetentionPolicyLogCategory: Enum "Retention Policy Log Category";
    begin
        exit(RetentionPolicyLogCategory::"Retention Policy - Setup")
    end;

    procedure AddRetentionPolicyOnRegisterManualSetup(ManualSetup: Codeunit "Manual Setup")
    var
        ManualSetupCategory: Enum "Manual Setup Category";
        CurrModuleInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(CurrModuleInfo);
        ManualSetup.Insert(ManualSetupNameTxt, ManualSetupDescriptionTxt, ManualSetupKeyWordsTxt, Page::"Retention Policy Setup List", CurrModuleInfo.Id, ManualSetupCategory::Uncategorized);
    end;

    procedure VerifyRetentionPolicySetupOnbeforeDeleteRetentionPeriod(var RetentionPeriod: Record "Retention Period")
    var
        RetentionPolicySetup: Record "Retention Policy Setup";
        RetentionPolicySetupLine: Record "Retention Policy Setup Line";
        RetentionPolicyLog: Codeunit "Retention Policy Log";
    begin
        if RetentionPeriod.IsTemporary() then
            exit;

        if GetCurrentModuleExecutionContext() <> ExecutionContext::Normal then
            exit;

        RetentionPolicySetup.Setrange("Retention Period", RetentionPeriod.Code);
        if not RetentionPolicySetup.IsEmpty() then
            RetentionPolicyLog.LogError(LogCategory(), StrSubstNo(RetentionPeriodUsedErr, RetentionPeriod.Code));

        RetentionPolicySetupLine.Setrange("Retention Period", RetentionPeriod.Code);
        if not RetentionPolicySetupLine.IsEmpty() then
            RetentionPolicyLog.LogError(LogCategory(), StrSubstNo(RetentionPeriodUsedErr, RetentionPeriod.Code));
    end;

    procedure VerifyRetentionPolicySetupOnBeforeModifyRetentionPeriod(var RetentionPeriod: Record "Retention Period")
    var
        RetentionPolicySetupLine: Record "Retention Policy Setup Line";
        RetentionPolicyLog: Codeunit "Retention Policy Log";
    begin
        if RetentionPeriod.IsTemporary() then
            exit;

        if GetCurrentModuleExecutionContext() <> ExecutionContext::Normal then
            exit;

        RetentionPolicySetupLine.Setrange("Retention Period", RetentionPeriod.Code);
        RetentionPolicySetupLine.SetRange(Locked, true);
        if not RetentionPolicySetupLine.IsEmpty() then
            RetentionPolicyLog.LogError(LogCategory(), StrSubstNo(RetentionPeriodLockedErr, RetentionPeriod.Code));
    end;

    procedure VerifyRetentionPolicyAllowedTablesOnBeforeInsertRetenPolSetup(var RetentionPolicySetup: Record "Retention Policy Setup")
    var
        RetentionPolicyLog: Codeunit "Retention Policy Log";
        RetenPolAllowedTables: Codeunit "Reten. Pol. Allowed Tables";
        RetenPolAllowedTablesImpl: Codeunit "Reten. Pol. Allowed Tbl. Impl.";
        TableFilters: JsonArray;
    begin
        RetentionPolicySetup.CalcFields("Table Caption");
        if not RetenPolAllowedTables.IsAllowedTable(RetentionPolicySetup."Table ID") then
            RetentionPolicyLog.LogError(LogCategory(), StrSubstNo(TableNotAllowedErrorLbl, RetentionPolicySetup."Table ID", RetentionPolicySetup."Table Caption"));
        TableFilters := RetenPolAllowedTablesImpl.GetTableFilters(RetentionPolicySetup."Table Id");
        if TableFilters.Count <> 0 then
            RetentionPolicySetup."Apply to all records" := false;
    end;

    procedure InsertDefaultTableFiltersOnAfterInsertRetenPolSetup(var RetentionPolicySetup: Record "Retention Policy Setup")
    var
        RetentionPolicySetupLine: Record "Retention Policy Setup Line";
        RetenPolAllowedTablesImpl: Codeunit "Reten. Pol. Allowed Tbl. Impl.";
        RetentionPolicyLog: Codeunit "Retention Policy Log";
        RetPeriodCalc: DateFormula;
        TableFilters: JsonArray;
        JsonToken: JsonToken;
        JsonObject: JsonObject;
        OutStream: OutStream;
        i: Integer;
        TableId: Integer;
        RetentionPeriodEnum: enum "Retention Period Enum";
        DateFieldNo: Integer;
        Enabled: Boolean;
        Locked: Boolean;
        TableFilter: Text;
    begin
        if RetentionPolicySetup.IsTemporary then
            exit;

        TableFilters := RetenPolAllowedTablesImpl.GetTableFilters(RetentionPolicySetup."Table Id");
        if TableFilters.Count = 0 then
            exit;

        RetentionPolicySetupLine.SetRange("Table Id", RetentionPolicySetup."Table Id");
        RetentionPolicySetupLine.validate("Table ID", RetentionPolicySetup."Table Id");
        if RetentionPolicySetupLine.FindLast() then;
        for i := 1 to TableFilters.Count() do begin
            RetentionPolicySetupLine.Init();
            RetentionPolicySetupLine."Line No." += 10000;
            TableFilters.Get(i - 1, JsonToken);
            JsonObject := JsonToken.AsObject();
            RetenPolAllowedTablesImpl.ParseTableFilter(JsonObject, TableId, RetentionPeriodEnum, RetPeriodCalc, DateFieldNo, Enabled, Locked, TableFilter);
            if TableId <> RetentionPolicySetupLine."Table ID" then
                RetentionPolicyLog.LogWarning(LogCategory(), StrSubstNo(RetenPolAllowedTableFilterMismatchLbl, RetentionPolicySetupLine."Table ID", TableId))
            else begin
                RetentionPolicySetupLine.Validate("Table ID", TableId);
                RetentionPolicySetupLine.Validate("Retention Period", FindOrCreateRetentionPeriod(RetentionPeriodEnum, RetPeriodCalc));
                RetentionPolicySetupLine.Validate("Date Field No.", DateFieldNo);
                RetentionPolicySetupLine.Validate(Locked, Locked);
                if RetentionPolicySetupLine.Locked then
                    RetentionPolicySetupLine.Validate(Enabled, true)
                else
                    RetentionPolicySetupLine.Validate(Enabled, Enabled);
                RetentionPolicySetupLine."Table Filter".CreateOutStream(OutStream, TextEncoding::UTF8);
                OutStream.Write(TableFilter);
                RetentionPolicySetupLine."Table Filter Text" := RetentionPolicySetupLine.GetTableFilterText();
                RetentionPolicySetupLine.Insert(true);
            end;
        end;
    end;

    local procedure FindOrCreateRetentionPeriod(RetentionPeriodEnum: enum "Retention Period Enum"; RetPeriodCalc: DateFormula): Code[20]
    var
        RetentionPeriod: Record "Retention Period";
    begin
        // find 
        RetentionPeriod.SetRange("Retention Period", RetentionPeriodEnum);
        if RetentionPeriodEnum = RetentionPeriodEnum::Custom then
            RetentionPeriod.SetRange("Ret. Period Calculation", RetPeriodCalc);
        if RetentionPeriod.FindFirst() then
            exit(RetentionPeriod.Code);

        // create
        RetentionPeriod.Code := CopyStr(format(RetentionPeriodEnum), 1, MaxStrLen(RetentionPeriod.Code));
        if RetentionPeriod.Get(RetentionPeriod.Code) then begin
            // ensure a unique code
            RetentionPeriod.Init();
            RetentionPeriod.Code := CopyStr(format(RetentionPeriodEnum), 1, MaxStrLen(RetentionPeriod.Code) - 2) + '01';
            While RetentionPeriod.Get(RetentionPeriod.Code) do
                RetentionPeriod.Code := IncStr(RetentionPeriod.Code);
        end;
        RetentionPeriod.Description := CopyStr(format(RetentionPeriodEnum), 1, MaxStrLen(RetentionPeriod.Description));
        RetentionPeriod.validate("Retention Period", RetentionPeriodEnum);
        if RetentionPeriod."Retention Period" = RetentionPeriod."Retention Period"::Custom then
            RetentionPeriod.validate("Ret. Period Calculation", RetPeriodCalc);
        RetentionPeriod.Insert(true);
        exit(RetentionPeriod.Code);
    end;

    procedure DeleteRetentionPolicySetup(var RetentionPolicySetup: Record "Retention Policy Setup")
    var
        RetentionPolicySetupLine: Record "Retention Policy Setup Line";
        RetentionPolicySetupImpl: Codeunit "Retention Policy Setup Impl.";
    begin
        if not RetentionPolicySetup.IsTemporary() then begin
            RetentionPolicySetupLine.Setrange("Table ID", RetentionPolicySetup."Table ID");
            if not RetentionPolicySetupLine.IsEmpty() then begin
                BindSubscription(RetentionPolicySetupImpl);
                RetentionPolicySetupImpl.AddTableIdToDeleteAllowedList(RetentionPolicySetup."Table Id");
                RetentionPolicySetupLine.DeleteAll(true);
                UnbindSubscription(RetentionPolicySetupImpl);
            end;
        end;
    end;

    procedure AddTableIdToDeleteAllowedList(TableId: Integer)
    begin
        DeleteAllowedList.Add(TableId);
    end;

    procedure NotifyOnMissingReadPermission(TableId: Integer)
    var
        RetentionPolicySetup: Record "Retention Policy Setup";
        RetenPolAllowedTables: Codeunit "Reten. Pol. Allowed Tables";
        ReadPermissionNotification: Notification;
        RetenPolFiltering: Interface "Reten. Pol. Filtering";
    begin
        RetenPolFiltering := RetenPolAllowedTables.GetRetenPolFiltering(TableId);
        if RetenPolFiltering.HasReadPermission(TableId) then
            exit;

        if RetentionPolicySetup.Get(TableId) then
            RetentionPolicySetup.CalcFields("Table Caption");

        ReadPermissionNotification.Message(StrSubstNo(ReadPermissionNotificationLbl, TableId, RetentionPolicySetup."Table Caption"));
        ReadPermissionNotification.Send();
    end;

    /// <Summary>
    /// This is an internal event that only this module is allowed to subscribe to. It is raised by a subscriber to the OnBeforeDeleteEvent of the Retention Policy Setup Line table.
    /// The manual subscriber AllowRetentionPolicySetupLineDelete is bound just before the DeleteAll() in procedure DeleteRetentionPolicySetup.
    /// These elements combined are to ensure that only procedure DeleteRetentionPolicySetup can delete locked lines from the table.
    /// You should only be able to delete locked lines when deleting the 'header' Retention Policy Setup record.
    /// </Summary>
    # pragma warning disable AA0150 // Parameter 'DeleteAllowed' is declared by reference but never changed in method 'OnVerifyDeleteAllowed'.
    [InternalEvent(false)]
    internal procedure OnVerifyDeleteAllowed(TableId: Integer; var DeleteAllowed: Boolean)
    # pragma warning restore AA0150
    begin
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Retention Policy Setup Impl.", 'OnVerifyDeleteAllowed', '', false, false)]
    local procedure AllowRetentionPolicySetupLineDelete(TableId: Integer; var DeleteAllowed: Boolean)
    begin
        DeleteAllowed := DeleteAllowedList.Contains(TableId);
    end;

    procedure CheckRecordLockedOnRetentionPolicySetupLine(RetentionPolicySetupLine: Record "Retention Policy Setup Line")
    var
        RetentionPolicyLog: Codeunit "Retention Policy Log";
        DeleteAllowed: Boolean;
    begin
        if RetentionPolicySetupLine.IsTemporary then
            exit;

        if RetentionPolicySetupLine.Locked then begin
            RetentionPolicySetupLine.CalcFields("Table Caption");
            OnVerifyDeleteAllowed(RetentionPolicySetupLine."Table ID", DeleteAllowed);
            if DeleteAllowed then begin
                RetentionPolicyLog.LogInfo(LogCategory(), StrSubstNo(DeleteAllowedInfoLbl, RetentionPolicySetupLine."Table ID", RetentionPolicySetupLine."Table Caption"));
                exit; // allow delete
            end;
            RetentionPolicyLog.LogError(LogCategory(), StrSubstNo(RetentionPolicySetupLineLockedErr, RetentionPolicySetupLine."Table ID", RetentionPolicySetupLine."Table Caption"));
        end;
    end;
}