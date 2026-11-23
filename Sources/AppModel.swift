import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class AppModel: ObservableObject {
    @Published var draft: FoodDraft = .example { didSet {
        if draft.selectedPrinter != oldValue.selectedPrinter {
            printerConnected=false; printerMessage="Проверка подключения…"
            Task { await checkPrinter() }
        }
        scheduleRefresh()
    } }
    @Published var raster: LabelRaster?
    @Published var validFood: ValidFood?
    @Published var validation = ""
    @Published var foods: [SavedFood] = []
    @Published var history: [PrintRecord] = []
    @Published var selectedFood: String?
    @Published var section = "editor"
    @Published var busy = false
    @Published var checking = false
    @Published var printerConnected = false
    @Published var printerMessage = "Проверка подключения…"
    @Published var notice = ""
    @Published var errorMessage = ""
    @Published var historySelection: String?
    @Published var historyDateNotice = false
    @Published var startupError = ""
    private(set) var database: LabelDatabase?
    private let printer = PrinterService()
    private var refreshTask: Task<Void,Never>?
    let databaseURL: URL
    var canPrint: Bool { raster != nil && validFood != nil && database != nil && !busy && !checking && startupError.isEmpty }
    init() {
        if let override=ProcessInfo.processInfo.environment["FOODLABEL_DATA_DIR"] {
            databaseURL=URL(fileURLWithPath:override).appendingPathComponent("foodlabel.sqlite")
        } else {
            databaseURL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("FoodLabel/foodlabel.sqlite")
        }
        do {
            let db=try LabelDatabase(url:databaseURL); database=db
            try db.recoverInterruptedJobs()
            if var restored=try db.loadDraft() { restored.useToday(); restored.copies="1"; draft=restored }
            try reload(); refresh()
        } catch { startupError=error.localizedDescription; errorMessage=startupError }
        Task { await checkPrinter(autoSelect:true) }
    }
    private func scheduleRefresh() {
        raster=nil; validFood=nil; validation="Обновление предпросмотра…"
        refreshTask?.cancel()
        refreshTask=Task { [weak self] in
            try? await Task.sleep(nanoseconds:180_000_000)
            guard !Task.isCancelled else { return }; self?.refresh()
        }
    }
    func refresh() {
        do { let value=try draft.validated(); raster=try LabelRenderer.render(value,profile:draft.selectedPrinter); validFood=value; validation="" }
        catch { raster=nil; validFood=nil; validation=error.localizedDescription }
        if let database {
            do { try database.saveDraft(draft) }
            catch { startupError=error.localizedDescription; errorMessage="Не удалось сохранить черновик. Печать отключена. \(error.localizedDescription)" }
        }
    }
    func reload() throws { guard let database else { return }; foods=try database.foods(); history=try database.jobs() }
    func changeBasis(_ basis: NutritionBasis) {
        do { var next=draft; try next.switchBasis(to:basis); draft=next; refresh() }
        catch { errorMessage=error.localizedDescription }
    }
    func newFood() {
        do {
            guard let database else { return }
            var next=FoodDraft(); next.printerProfile=draft.selectedPrinter; next.barcode=try database.nextBarcode()
            selectedFood=nil; historyDateNotice=false; draft=next; section="editor"; notice=""; refresh()
        } catch { errorMessage=error.localizedDescription }
    }
    func load(_ food: SavedFood) {
        var next=food.draft; next.printerProfile=draft.selectedPrinter; next.useToday(); next.copies="1"
        selectedFood=food.id; historyDateNotice=false; draft=next; section="editor"; notice=""; refresh()
    }
    func loadHistory(_ record: PrintRecord) {
        selectedFood=nil; draft=record.draft; draft.copies="1"; historyDateNotice=true; section="editor"; notice=""; refresh()
    }
    func saveFood(asNew: Bool = false) {
        do {
            guard let database else { return }; _=try draft.validated()
            selectedFood=try database.saveFood(id:asNew ? nil : selectedFood,draft:draft)
            try reload(); notice="Блюдо сохранено на этом Mac."
        } catch { errorMessage=error.localizedDescription }
    }
    func generateBarcode() {
        do { guard let database else { return }; draft.barcode=try database.nextBarcode(); refresh() }
        catch { errorMessage=error.localizedDescription }
    }
    func selectPrinter(_ profile: PrinterProfile) {
        guard !busy && !checking else { return }
        draft.printerProfile=profile; printerConnected=false; printerMessage="Проверка подключения…"; refresh()
        Task { await checkPrinter() }
    }
    func checkPrinter(autoSelect: Bool = false) async {
        guard !checking && !busy else { return }; checking=true
        if autoSelect {
            let profiles=await printer.connectedProfiles()
            if profiles.count == 1 { draft.printerProfile=profiles[0]; refresh() }
        }
        let queriedProfile=draft.selectedPrinter
        let result=await printer.probe(profile:queriedProfile)
        checking=false
        guard draft.selectedPrinter == queriedProfile else { await checkPrinter(); return }
        printerConnected=result.success; printerMessage=result.message
    }
    func printLabel() async {
        guard canPrint, let database, let raster, let value=validFood else { return }
        refreshTask?.cancel()
        let snapshot=draft
        busy=true; notice=""; defer { busy=false }
        do {
            let data=try snapshot.selectedPrinter == .niimbot ? NiimbotJob(raster:raster,copies:value.copies).data : raster.tspl(copies:value.copies)
            let id=try database.beginJob(draft:snapshot,raster:raster,bytes:data)
            try reload()
            let result=await printer.send(data,profile:snapshot.selectedPrinter)
            // A partial send is uncertain; never retry it automatically.
            let status=result.success ? "sent" : (result.transferred > 0 ? "uncertain" : "error")
            do {
                try database.finishJob(id:id,status:status,detail:result.message,transferred:result.transferred)
                try reload()
            } catch {
                startupError=error.localizedDescription
                errorMessage="Результат передачи: \(result.message) Не удалось обновить историю. Не повторяйте печать, пока не проверите принтер. \(error.localizedDescription)"
                return
            }
            printerConnected=result.success
            if result.success { notice="Передано принтеру: \(value.copies) шт. Запись сохранена в истории." }
            else { errorMessage=result.message }
        } catch { errorMessage="Печать не начата: \(error.localizedDescription)" }
    }
    func exportPNG() {
        refresh(); guard let raster else { return }
        let panel=NSSavePanel(); panel.allowedContentTypes=[.png]; panel.nameFieldStringValue="\(draft.name)-\(draft.barcode).png"
        if panel.runModal() == .OK, let url=panel.url {
            do { try raster.png().write(to:url,options:.atomic); notice="Этикетка сохранена в PNG." }
            catch { errorMessage=error.localizedDescription }
        }
    }
    func backup() {
        guard let database else { return }
        let panel=NSSavePanel(); panel.nameFieldStringValue="FoodLabel-backup.sqlite"
        if panel.runModal() == .OK, let url=panel.url {
            do { try database.backup(to:url); notice="Резервная копия базы сохранена." }
            catch { errorMessage=error.localizedDescription }
        }
    }
    func showDatabase() { NSWorkspace.shared.activateFileViewerSelecting([databaseURL]) }
}
