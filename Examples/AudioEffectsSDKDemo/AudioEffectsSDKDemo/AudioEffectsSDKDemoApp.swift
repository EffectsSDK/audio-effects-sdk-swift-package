import SwiftUI

func makePipelineController() -> AudioPipelineController{
	let pipelineController = AudioPipelineController()
	Task {
		await pipelineController.initialize()
	}
	return pipelineController
}

class Records: ObservableObject {
	@Published var items: [RecordItem]
	
	init(_ newItems: [RecordItem] = [RecordItem]()) {
		items = newItems
	}
}

func makeRecords() -> Records {
	let records = Records()
	Task {
		let loadedItems = await loadRecordItems()
		await MainActor.run {
			records.items.append(contentsOf: loadedItems)
		}
	}
	return records
}

@main
struct AudioEffectsSDKDemoApp: App {
	@StateObject private var pipelineController = makePipelineController()
	@StateObject private var records = makeRecords()
	
    var body: some Scene {
        WindowGroup {
			ContentView(pipelineController: pipelineController, records: records)
		}
    }
}
