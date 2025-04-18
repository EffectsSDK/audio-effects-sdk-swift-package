import SwiftUI

struct RenameFileView: View {
	@Binding var name: String
	var onCancel: ()->Void
	var onApply: ()->Void
	
	
	var body: some View {
		VStack() {
			Text("Rename file")
				.font(.title2)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.leading)
			TextField("Rename file", text: $name)
			Divider().background(.black).frame(height:1)
			HStack{
				Spacer()
				Button(action: onCancel) { Text("CANCEL") }.padding()
				Button(action: onApply) { Text("APPLY") }.padding(.trailing)
			}
		}.padding()
	}
}

#Preview {
	RenameFileView(name: .constant("Test name"), onCancel: {}, onApply: {})
}
