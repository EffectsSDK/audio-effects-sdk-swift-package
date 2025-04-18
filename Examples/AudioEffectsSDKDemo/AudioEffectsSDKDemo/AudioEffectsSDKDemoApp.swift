import SwiftUI

func makePipelineController() -> AudioPipelineController{
	let pipelineController = AudioPipelineController()
	Task {
		await pipelineController.initialize()
	}
	return pipelineController
}

@main
struct AudioEffectsSDKDemoApp: App {
	@StateObject private var pipelineController = makePipelineController()
	
    var body: some Scene {
        WindowGroup {
			ContentView(pipelineController: pipelineController)
        }
    }
}
