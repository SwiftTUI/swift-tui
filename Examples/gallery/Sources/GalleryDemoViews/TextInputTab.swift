import SwiftTUI

struct TextInputTab: View {
  @State private var searchText = "SwiftTUI"
  @State private var ownerName = "Ada Lovelace"
  @State private var emailAddress = ""
  @State private var accessToken = "secret"
  @State private var plainField = "plain style"
  @State private var roundedField = "rounded border"
  @State private var disabledField = "read-only"
  @State private var notes =
    """
    TextEditor uses the same reducer-backed text model as TextField.
    Try arrow keys, return, backspace, and bracketed paste here.
    """

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 1) {
        header
        Divider()
        singleLineSection
        Divider()
        secureSection
        Divider()
        styleSection
        Divider()
        multilineSection
        Divider()
        liveSummary
        Spacer(minLength: 0)
      }
      .padding(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Text Input")
        .foregroundStyle(.foreground)
      Text("TextField, SecureField, TextEditor, prompts, styles, focus, and paste.")
        .foregroundStyle(.separator)
    }
  }

  private var singleLineSection: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Single-line fields").foregroundStyle(.muted)
      VStack(alignment: .leading, spacing: 0) {
        TextField("Search controls", text: $searchText)
          .frame(width: 34)
        TextField(text: $ownerName, prompt: Text("Name")) {
          Text("Owner")
        }
        .frame(width: 34)
        TextField(text: $emailAddress, prompt: Text("name@example.com")) {
          Text("Email")
        }
        .frame(width: 34)
      }
    }
  }

  private var secureSection: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Secure entry").foregroundStyle(.muted)
      HStack(alignment: .top, spacing: 3) {
        SecureField(text: $accessToken, prompt: Text("token")) {
          Text("Access token")
        }
        .frame(width: 34)
        VStack(alignment: .leading, spacing: 0) {
          Text("stored characters")
            .foregroundStyle(.separator)
          Text("\(accessToken.count)")
            .foregroundStyle(.cyan)
        }
      }
    }
  }

  private var styleSection: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Styles and enabled state").foregroundStyle(.muted)
      HStack(alignment: .top, spacing: 3) {
        VStack(alignment: .leading, spacing: 0) {
          Text("Plain").foregroundStyle(.separator)
          TextField("plain", text: $plainField)
            .textFieldStyle(PlainTextFieldStyle())
            .frame(width: 24)
        }
        VStack(alignment: .leading, spacing: 0) {
          Text("Rounded").foregroundStyle(.separator)
          TextField("rounded", text: $roundedField)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .frame(width: 24)
        }
        VStack(alignment: .leading, spacing: 0) {
          Text("Disabled").foregroundStyle(.separator)
          TextField("disabled", text: $disabledField)
            .disabled(true)
            .frame(width: 20)
        }
      }
    }
  }

  private var multilineSection: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Multiline editor").foregroundStyle(.muted)
      TextEditor(text: $notes)
        .frame(width: 64, height: 7)
    }
  }

  private var liveSummary: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Live binding summary").foregroundStyle(.muted)
      HStack(spacing: 2) {
        Text("search:")
          .foregroundStyle(.separator)
        Text(searchText)
      }
      HStack(spacing: 2) {
        Text("owner:")
          .foregroundStyle(.separator)
        Text(ownerName)
      }
      HStack(spacing: 2) {
        Text("notes chars:")
          .foregroundStyle(.separator)
        Text("\(notes.count)")
      }
    }
  }
}
