import SwiftUI

@main struct FoodLabelApp: App {
    @StateObject private var model=AppModel()
    var body: some Scene {
        Window("FoodLabel — этикетки для еды",id:"main") {
            ContentView(model:model).environment(\.locale,Locale(identifier:"ru_RU"))
        }.defaultSize(width:1180,height:780)
        .commands { CommandGroup(replacing:.newItem) { Button("Новое блюдо") { model.newFood() }.keyboardShortcut("n") } }
    }
}
