// Direct-data collection surfaces. These signatures deliberately expose only
// existing public building blocks (`ForEach`, `TableRow`, and `.tag`) while the
// collection containers recognize the resulting total indexed source
// internally for viewport-backed realization.

extension List {
  public init<Data, ID, RowContent>(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    @ViewBuilder rowContent: @escaping @MainActor (Data.Element) -> RowContent
  )
  where
    Data: RandomAccessCollection,
    ID: Hashable & Sendable,
    RowContent: View,
    SelectionValue == Never,
    Content == ForEach<Data, ID, RowContent>
  {
    self.init {
      ForEach(data, id: id, content: rowContent)
    }
    usesIndexedDataSource = true
  }

  public init<Data, RowContent>(
    _ data: Data,
    id: KeyPath<Data.Element, SelectionValue>,
    selection: Binding<SelectionValue?>,
    onActivate: (@MainActor (SelectionValue) -> Void)? = nil,
    @ViewBuilder rowContent: @escaping @MainActor (Data.Element) -> RowContent
  )
  where
    Data: RandomAccessCollection,
    SelectionValue: Sendable,
    RowContent: View,
    Content
      == ForEach<
        Data,
        SelectionValue,
        ModifiedContent<RowContent, TagValueModifier<SelectionValue>>
      >
  {
    self.init(selection: selection, onActivate: onActivate) {
      ForEach(data, id: id) { element in
        rowContent(element).modifier(
          TagValueModifier(
            tag: element[keyPath: id],
            includeOptional: true
          )
        )
      }
    }
    usesIndexedDataSource = true
  }

  public init<Data, RowContent>(
    _ data: Data,
    id: KeyPath<Data.Element, SelectionValue>,
    selection: Binding<Set<SelectionValue>>,
    onActivate: (@MainActor (SelectionValue) -> Void)? = nil,
    @ViewBuilder rowContent: @escaping @MainActor (Data.Element) -> RowContent
  )
  where
    Data: RandomAccessCollection,
    SelectionValue: Sendable,
    RowContent: View,
    Content
      == ForEach<
        Data,
        SelectionValue,
        ModifiedContent<RowContent, TagValueModifier<SelectionValue>>
      >
  {
    self.init(selection: selection, onActivate: onActivate) {
      ForEach(data, id: id) { element in
        rowContent(element).modifier(
          TagValueModifier(
            tag: element[keyPath: id],
            includeOptional: true
          )
        )
      }
    }
    usesIndexedDataSource = true
  }
}

extension List {
  public init<Data, RowContent>(
    _ data: Data,
    @ViewBuilder rowContent: @escaping @MainActor (Data.Element) -> RowContent
  )
  where
    Data: RandomAccessCollection,
    Data.Element: Identifiable,
    Data.Element.ID: Sendable,
    RowContent: View,
    SelectionValue == Never,
    Content == ForEach<Data, Data.Element.ID, RowContent>
  {
    self.init(data, id: \.id, rowContent: rowContent)
  }

  public init<Data, RowContent>(
    _ data: Data,
    selection: Binding<Data.Element.ID?>,
    onActivate: (@MainActor (Data.Element.ID) -> Void)? = nil,
    @ViewBuilder rowContent: @escaping @MainActor (Data.Element) -> RowContent
  )
  where
    Data: RandomAccessCollection,
    Data.Element: Identifiable,
    Data.Element.ID: Sendable,
    RowContent: View,
    SelectionValue == Data.Element.ID,
    Content
      == ForEach<
        Data,
        Data.Element.ID,
        ModifiedContent<RowContent, TagValueModifier<Data.Element.ID>>
      >
  {
    self.init(
      data,
      id: \.id,
      selection: selection,
      onActivate: onActivate,
      rowContent: rowContent
    )
  }

  public init<Data, RowContent>(
    _ data: Data,
    selection: Binding<Set<Data.Element.ID>>,
    onActivate: (@MainActor (Data.Element.ID) -> Void)? = nil,
    @ViewBuilder rowContent: @escaping @MainActor (Data.Element) -> RowContent
  )
  where
    Data: RandomAccessCollection,
    Data.Element: Identifiable,
    Data.Element.ID: Sendable,
    RowContent: View,
    SelectionValue == Data.Element.ID,
    Content
      == ForEach<
        Data,
        Data.Element.ID,
        ModifiedContent<RowContent, TagValueModifier<Data.Element.ID>>
      >
  {
    self.init(
      data,
      id: \.id,
      selection: selection,
      onActivate: onActivate,
      rowContent: rowContent
    )
  }
}

extension Table {
  public init<Data, ID, CellContent>(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    columns: [TableColumn],
    @ViewBuilder cells: @escaping @MainActor (Data.Element) -> CellContent
  )
  where
    Data: RandomAccessCollection,
    ID: Hashable & Sendable,
    CellContent: View,
    SelectionValue == Never,
    Rows == ForEach<Data, ID, TableRow<CellContent>>
  {
    self.init(columns: columns) {
      ForEach(data, id: id) { element in
        TableRow {
          cells(element)
        }
      }
    }
    usesIndexedDataSource = true
  }

  public init<Data, CellContent>(
    _ data: Data,
    id: KeyPath<Data.Element, SelectionValue>,
    selection: Binding<SelectionValue?>,
    columns: [TableColumn],
    @ViewBuilder cells: @escaping @MainActor (Data.Element) -> CellContent
  )
  where
    Data: RandomAccessCollection,
    SelectionValue: Sendable,
    CellContent: View,
    Rows
      == ForEach<
        Data,
        SelectionValue,
        ModifiedContent<TableRow<CellContent>, TagValueModifier<SelectionValue>>
      >
  {
    self.init(selection: selection, columns: columns) {
      ForEach(data, id: id) { element in
        TableRow {
          cells(element)
        }
        .modifier(
          TagValueModifier(
            tag: element[keyPath: id],
            includeOptional: true
          )
        )
      }
    }
    usesIndexedDataSource = true
  }

  public init<Data, CellContent>(
    _ data: Data,
    id: KeyPath<Data.Element, SelectionValue>,
    selection: Binding<Set<SelectionValue>>,
    columns: [TableColumn],
    @ViewBuilder cells: @escaping @MainActor (Data.Element) -> CellContent
  )
  where
    Data: RandomAccessCollection,
    SelectionValue: Sendable,
    CellContent: View,
    Rows
      == ForEach<
        Data,
        SelectionValue,
        ModifiedContent<TableRow<CellContent>, TagValueModifier<SelectionValue>>
      >
  {
    self.init(selection: selection, columns: columns) {
      ForEach(data, id: id) { element in
        TableRow {
          cells(element)
        }
        .modifier(
          TagValueModifier(
            tag: element[keyPath: id],
            includeOptional: true
          )
        )
      }
    }
    usesIndexedDataSource = true
  }
}

extension Table {
  public init<Data, CellContent>(
    _ data: Data,
    columns: [TableColumn],
    @ViewBuilder cells: @escaping @MainActor (Data.Element) -> CellContent
  )
  where
    Data: RandomAccessCollection,
    Data.Element: Identifiable,
    Data.Element.ID: Sendable,
    CellContent: View,
    SelectionValue == Never,
    Rows == ForEach<Data, Data.Element.ID, TableRow<CellContent>>
  {
    self.init(data, id: \.id, columns: columns, cells: cells)
  }

  public init<Data, CellContent>(
    _ data: Data,
    selection: Binding<Data.Element.ID?>,
    columns: [TableColumn],
    @ViewBuilder cells: @escaping @MainActor (Data.Element) -> CellContent
  )
  where
    Data: RandomAccessCollection,
    Data.Element: Identifiable,
    Data.Element.ID: Sendable,
    CellContent: View,
    SelectionValue == Data.Element.ID,
    Rows
      == ForEach<
        Data,
        Data.Element.ID,
        ModifiedContent<TableRow<CellContent>, TagValueModifier<Data.Element.ID>>
      >
  {
    self.init(data, id: \.id, selection: selection, columns: columns, cells: cells)
  }

  public init<Data, CellContent>(
    _ data: Data,
    selection: Binding<Set<Data.Element.ID>>,
    columns: [TableColumn],
    @ViewBuilder cells: @escaping @MainActor (Data.Element) -> CellContent
  )
  where
    Data: RandomAccessCollection,
    Data.Element: Identifiable,
    Data.Element.ID: Sendable,
    CellContent: View,
    SelectionValue == Data.Element.ID,
    Rows
      == ForEach<
        Data,
        Data.Element.ID,
        ModifiedContent<TableRow<CellContent>, TagValueModifier<Data.Element.ID>>
      >
  {
    self.init(data, id: \.id, selection: selection, columns: columns, cells: cells)
  }
}
