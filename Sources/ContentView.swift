// THESIS: a native label workbench; input, live paper and print controls stay visible together.
// OWN-WORLD: macOS system typography and surfaces, restrained green accent, crisp white thermal label.
// STORY: select food, enter known nutrition, inspect both bases, then explicitly print.
// FIRST VIEWPORT: saved-food sidebar, labeled editor, paper preview and copy controls.
// FORM: native macOS split-view utility, pinned by approved product scope.
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var search=""
    private let accent=Color(red:0.12,green:0.40,blue:0.31)
    var body: some View {
        HSplitView {
            sidebar.frame(minWidth:205,idealWidth:225,maxWidth:290)
            Group { if model.section == "history" { historyView } else { editorView } }
                .frame(minWidth:800,maxWidth:.infinity,maxHeight:.infinity)
        }
        .frame(minWidth:1040,minHeight:720)
        .tint(accent)
        .toolbar {
            ToolbarItem(placement:.navigation) { Text("FoodLabel").font(.headline) }
            ToolbarItemGroup(placement:.primaryAction) {
                Button { model.backup() } label: { Label("Резервная копия",systemImage:"externaldrive") }.help("Сохранить копию локальной базы")
                Button { model.showDatabase() } label: { Label("База данных",systemImage:"folder") }.help("Показать локальную базу")
            }
        }
        .alert("Не удалось выполнить действие",isPresented:Binding(get:{!model.errorMessage.isEmpty},set:{if !$0 {model.errorMessage=""}})) {
            Button("Понятно",role:.cancel) { model.errorMessage="" }
        } message: { Text(model.errorMessage) }
    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:0) {
            VStack(alignment:.leading,spacing:12) {
                Button { model.newFood() } label: { Label("Новое блюдо",systemImage:"plus").frame(maxWidth:.infinity,alignment:.leading) }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut("n")
                Button { model.section="history" } label: {
                    HStack { Label("История печати",systemImage:"clock.arrow.circlepath"); Spacer(); Text("\(model.history.count)").foregroundStyle(.secondary) }
                }.buttonStyle(.plain).padding(.vertical,5)
                TextField("Поиск блюд",text:$search).textFieldStyle(.roundedBorder)
            }.padding(16)
            Divider()
            Text("Сохранённые блюда").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal,16).padding(.top,18).padding(.bottom,8)
            ScrollView {
                LazyVStack(spacing:4) {
                    if model.foods.isEmpty {
                        Text("Сохраните блюдо, чтобы быстро напечатать его снова.").font(.callout).foregroundStyle(.secondary).padding(16)
                    }
                    ForEach(model.foods.filter {search.isEmpty || $0.draft.name.localizedCaseInsensitiveContains(search)}) { food in
                        Button { model.load(food) } label: {
                            VStack(alignment:.leading,spacing:5) {
                                Text(food.draft.name).font(.body.weight(.medium)).lineLimit(2).foregroundStyle(.primary)
                                Text("\(food.draft.weight) г · \(food.draft.barcode)").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth:.infinity,alignment:.leading).padding(10)
                                .background(model.selectedFood == food.id && model.section == "editor" ? accent.opacity(0.12) : .clear,in:RoundedRectangle(cornerRadius:7))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal,8)
            }
            Divider()
            Label("Хранится на этом Mac",systemImage:"internaldrive").font(.caption).foregroundStyle(.secondary).padding(16)
        }.background(Color(nsColor:.windowBackgroundColor)).disabled(model.busy)
    }
    private var editorView: some View {
        HStack(alignment:.top,spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:25) {
                    VStack(alignment:.leading,spacing:5) {
                        Text("Этикетка блюда").font(.title2.weight(.semibold))
                        Text("Введите известные КБЖУ — остальные значения рассчитаются автоматически.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                    VStack(alignment:.leading,spacing:15) {
                        field("Название",text:$model.draft.name,placeholder:"Например, шаурма ленивая")
                        field("Вес порции, г",text:$model.draft.weight,placeholder:"250")
                    }
                    VStack(alignment:.leading,spacing:14) {
                        Text("КБЖУ указаны").font(.headline)
                        Picker("КБЖУ указаны",selection:Binding(get:{model.draft.basis},set:{model.changeBasis($0)})) {
                            ForEach(NutritionBasis.allCases,id:\.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden()
                        HStack(spacing:12) {
                            field("Калории, ккал",text:$model.draft.kcal,placeholder:"123")
                            field("Белки, г",text:$model.draft.protein,placeholder:"12,3")
                        }
                        HStack(spacing:12) {
                            field("Жиры, г",text:$model.draft.fat,placeholder:"3,4")
                            field("Углеводы, г",text:$model.draft.carbs,placeholder:"11")
                        }
                        Text(model.draft.basis == .per100 ? "Изменение веса пересчитает значения на порцию." : "Изменение веса пересчитает значения на 100 г.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                    VStack(alignment:.leading,spacing:14) {
                        DatePicker("Дата на этикетке",selection:$model.draft.date,displayedComponents:.date).environment(\.locale,Locale(identifier:"ru_RU")).environment(\.timeZone,model.draft.labelTimeZone)
                        if model.historyDateNotice {
                            HStack(alignment:.top) {
                                Text("Открыта запись из истории. Дата сохранена.").font(.caption).foregroundStyle(.secondary)
                                Button("Сегодня") { model.draft.useToday(); model.historyDateNotice=false }.controlSize(.small)
                            }
                        }
                        HStack(alignment:.bottom,spacing:10) {
                            field("Внутренний штрихкод",text:$model.draft.barcode,placeholder:"6 цифр")
                            Button { model.generateBarcode() } label: { Image(systemName:"arrow.clockwise") }.help("Создать новый внутренний код").padding(.bottom,2)
                        }
                        VStack(alignment:.leading,spacing:8) {
                            field("Ссылка на блюдо (QR)",text:Binding(get:{model.draft.qrLink ?? ""},set:{model.draft.qrLink=$0}),placeholder:"Вставьте ссылку из приложения")
                            HStack {
                                Button("Вставить") {
                                    if let link=NSPasteboard.general.string(forType:.string) { model.draft.qrLink=link }
                                }.help("Вставить ссылку из буфера обмена")
                                if !(model.draft.qrLink ?? "").isEmpty {
                                    Button("Убрать QR") { model.draft.qrLink=nil }
                                }
                            }
                            Text("Необязательно. QR откроет ссылку на блюдо; на телефоне может понадобиться соответствующее приложение.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        }
                    }
                    HStack {
                        Button(model.selectedFood == nil ? "Сохранить блюдо" : "Сохранить изменения") { model.saveFood() }.disabled(model.validFood == nil).keyboardShortcut("s")
                        if model.selectedFood != nil { Button("Сохранить копию") { model.saveFood(asNew:true) }.disabled(model.validFood == nil) }
                    }
                }.padding(24)
            }.frame(minWidth:350,idealWidth:385,maxWidth:440).disabled(model.busy)
            Divider()
            previewColumn.frame(minWidth:420,maxWidth:.infinity,maxHeight:.infinity)
        }.background(Color(nsColor:.controlBackgroundColor))
    }
    private func field(_ title:String,text:Binding<String>,placeholder:String) -> some View {
        VStack(alignment:.leading,spacing:7) {
            Text(title).font(.subheadline.weight(.medium))
            TextField(placeholder,text:text).textFieldStyle(.roundedBorder).controlSize(.large).accessibilityLabel(title)
        }
    }
    private var previewColumn: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack { Text("Предпросмотр").font(.headline); Spacer(); Text("58 × 30 мм").font(.callout).foregroundStyle(.secondary) }
            ZStack {
                RoundedRectangle(cornerRadius:10).fill(Color(nsColor:.windowBackgroundColor))
                if let raster=model.raster {
                    Image(nsImage:raster.image).resizable().interpolation(.none).aspectRatio(58/30,contentMode:.fit)
                        .background(.white).padding(20).accessibilityLabel("Предпросмотр печатной этикетки")
                } else {
                    VStack(spacing:10) { Image(systemName:"tag").font(.system(size:30)); Text("Заполните данные блюда").font(.headline) }.foregroundStyle(.secondary)
                }
            }.frame(height:255)
            if let food=model.validFood {
                VStack(alignment:.leading,spacing:10) {
                    Text("На порцию \(Numbers.display(food.grams)) г").font(.subheadline.weight(.semibold))
                    HStack {
                        metric("ккал",Numbers.display(food.perPortion.kcal))
                        metric("белки, г",Numbers.display(food.perPortion.protein))
                        metric("жиры, г",Numbers.display(food.perPortion.fat))
                        metric("углеводы, г",Numbers.display(food.perPortion.carbs))
                    }
                }
            } else if !model.validation.isEmpty {
                Label(model.validation,systemImage:"info.circle").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Divider()
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    Image(systemName:"printer").foregroundStyle(model.printerConnected ? accent : .secondary)
                    Text("Xprinter XP-365B").font(.headline)
                    Spacer()
                    Button { Task { await model.checkPrinter() } } label: { if model.checking { ProgressView().controlSize(.small) } else { Image(systemName:"arrow.clockwise") } }.disabled(model.checking || model.busy).help("Проверить подключение")
                }
                Text(model.printerMessage).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                HStack(spacing:12) {
                    Text("Копий")
                    TextField("1",text:$model.draft.copies).textFieldStyle(.roundedBorder).frame(width:54).accessibilityLabel("Количество копий")
                    Spacer()
                    Button("Сохранить PNG") { model.exportPNG() }.disabled(model.raster == nil || model.busy)
                }.disabled(model.busy)
                Button { Task { await model.printLabel() } } label: {
                    HStack { if model.busy { ProgressView().controlSize(.small) } else { Image(systemName:"printer.fill") }; Text(model.busy ? "Отправка…" : "Напечатать этикетки").fontWeight(.semibold) }.frame(maxWidth:.infinity).padding(.vertical,7)
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canPrint)
                Text("Каждое задание сохраняется в локальной истории.").font(.caption).foregroundStyle(.secondary)
            }
            if !model.notice.isEmpty { Label(model.notice,systemImage:"checkmark.circle").foregroundStyle(accent).font(.callout).fixedSize(horizontal:false,vertical:true) }
            if !model.startupError.isEmpty { Text(model.startupError).foregroundStyle(.red).font(.caption) }
            Spacer(minLength:0)
        }.padding(24)
    }
    private func metric(_ label:String,_ value:String) -> some View {
        VStack(alignment:.leading,spacing:5) { Text(value).font(.title3.weight(.semibold)).monospacedDigit(); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private var historyView: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { VStack(alignment:.leading,spacing:5) { Text("История печати").font(.title2.weight(.semibold)); Text("Снимки этикеток и результаты отправки. Всё хранится локально.").font(.callout).foregroundStyle(.secondary) }; Spacer(); Button("К редактору") { model.section="editor" } }
            if model.history.isEmpty {
                VStack(spacing:12) { Image(systemName:"clock.arrow.circlepath").font(.system(size:36)); Text("Пока нет заданий печати").font(.headline); Text("Первое задание появится здесь после нажатия «Напечатать этикетки».").foregroundStyle(.secondary) }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                HSplitView {
                    List(selection:$model.historySelection) {
                        ForEach(model.history) { job in
                            VStack(alignment:.leading,spacing:6) {
                                HStack { Text(job.draft.name).fontWeight(.medium); Spacer(); Text("\(job.draft.copies) шт.").foregroundStyle(.secondary) }
                                Text(job.created.formatted(date:.numeric,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                                Text(job.statusTitle).font(.caption).foregroundStyle(job.status == "sent" ? accent : .orange)
                            }.padding(.vertical,5).tag(job.id)
                        }
                    }.frame(minWidth:300)
                    if let selected=model.history.first(where:{$0.id == model.historySelection}) ?? model.history.first {
                        VStack(alignment:.leading,spacing:18) {
                            Text(selected.draft.name).font(.headline)
                            if let image=NSImage(data:selected.png) { Image(nsImage:image).resizable().interpolation(.none).aspectRatio(58/30,contentMode:.fit).background(.white) }
                            Text(selected.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                            Text("Передано: \(selected.transferred) байт").font(.caption).foregroundStyle(.secondary)
                            Text("«Отправлено» означает передачу по USB. Фактический выход этикеток проверяется на принтере.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                            Button("Открыть для повторной печати") { model.loadHistory(selected) }.buttonStyle(.borderedProminent)
                            Spacer()
                        }.padding(20).frame(minWidth:360,maxWidth:500)
                    }
                }
            }
        }.padding(24)
    }
}
