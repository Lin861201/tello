import UIKit
import AVFoundation

class ViewController: UIViewController {
    @IBOutlet weak var csvNameLabel: UILabel!
    @IBOutlet weak var musicNameLabel: UILabel!
    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var flyBt: UISwitch!
    @IBOutlet weak var logTextView: UITextView!
    @IBOutlet weak var safeSegment: UISegmentedControl!
    
    //預設飛行速度
    let defaultSpeedValue = 50
    
    //timer計時器
    var timer: Timer?
    var t = 0.0
    
    //音樂
    let music_FileName = "Ed Sheeran - Beautiful People"
    var audioPlayer: AVAudioPlayer!
    
    //csv處理
    let csv_FileName = "Stepsheet"
    var content = ""
    var csv = [[String]]()//CSV 主要資料陣列
    var handle = 1 //處理第幾行
    
    //tello Socket
    let default_socket = UDPClient(address: "192.168.10.1", port: 8889, myAddresss: "", myPort: 8889)//預設單機連接用
    var tello_Num = 0
    var tello = [UDPClient]() //群飛用 UDP 通訊陣列
    let port = 8889 //Tello 接收端口
    let sendPort_1st = 60000 // 發送端口起始編號 ex. 1:6000, 2:6001, 3: 6002
    var data = [String]()//回傳資料
    
//==================== 畫面載入 ==========================
    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true //螢幕恆亮不休眠
       
        //圓角
        timeLabel.layer.cornerRadius = 10
        logTextView.layer.cornerRadius = 10
        
        //prepare music
        let musicUrl = Bundle.main.url(forResource: music_FileName, withExtension: "mp3")
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: musicUrl!)
            audioPlayer.prepareToPlay()
        } catch {
            print("Error:", error.localizedDescription)
        }
        
        //read csv ＆ 存成二維陣列
        let csvUrl = Bundle.main.url(forResource: csv_FileName, withExtension: "csv")
        content = try! String(contentsOf: csvUrl!)
        csv = csv_To_Array(content)
        print(csv)
        
        //將預設檔案寫入資料夾
        saveFile(source: csvUrl!, destination: nil, fileName: "default.csv")
        saveFile(source: musicUrl!, destination: nil, fileName: "default.mp3")
        
        //創建tello 的 socket陣列
        create_Tello_UDP()
        recvData()
    }
//==================== 檔案處理 ==========================
    func saveFile(source: URL, destination: URL?, fileName: String){
        var dest = destination
        if dest==nil{
            dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        }
        dest = dest!.appendingPathComponent(fileName)
        
        if FileManager.default.fileExists(atPath: dest!.path){
            print(fileName + " already exists!")
        }else{
            do{
                try FileManager.default.copyItem(at: source, to: dest!)
            }
            catch{
                print("Error: \(error)")
            }
        }
    }
//======================= timer ==========================
    //timer開始
    func timerStart(){
        //安全模式 禁止更動
        safeSegment.isEnabled = false
        
        //接收資料區清空 ＆ 執行處理
        data_clear()
        timeHandle()
        
        //創建timer 每0.5秒執行一次
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true, block: {(_) in
            self.t += 0.5
            self.timeHandle()
            self.timeLabel.text = "Time : " + String(self.t) + "s"
        })
    }
    
    //結束timer
    func timerStop(){
    //安全模式 開放更動
        safeSegment.isEnabled = true
        
    //switch 關
        flyBt.setOn(false, animated: true)
        
    //停止音樂並關歸零
        audioPlayer.stop()
        audioPlayer.currentTime = 0
        
        if timer != nil{//當timer存在時 廢止
            timer?.invalidate()
            timer = nil
            
            //初始化
            t = 0.0
            handle = 1
            self.timeLabel.text = "Time : " + String(self.t) + "s"
        }
    }
    
    //timer處理
    func timeHandle(){
        if Double(csv[handle][0]) == t{//秒數到指令設定的秒數 執行
            print(csv[handle])
            
            for i in 0..<tello_Num{
                if csv[handle][i + 1] != ""{//i號機有指令
                    
                    //前一個沒做完(第一個指令除外), 安全模式不為"無" 啟動安全機制
                    if data[i] != "ok" && handle != 1 && safeSegment.selectedSegmentIndex != 0{
                        //1 群體迫降
                        if safeSegment.selectedSegmentIndex == 1{
                            print(String(i + 1) + "號脫隊, 全體迫降")
                            show_add(String(i + 1) + "號脫隊, 全體迫降")
                            send("stop")
                            send("land")
                            timerStop()
                            return
                            
                        //2 個體迫降
                        }else if safeSegment.selectedSegmentIndex == 2{
                            //已降落 略過
                            if data[i] == "landed"{
                                continue
                            }
                            
                            //執行單機迫降
                            print(String(i + 1) + "號脫隊 迫降")
                            show_add(String(i + 1) + "號脫隊 迫降")
                            send(i , "stop")
                            send(i, "land")
                            data[i] = "landed"//將對號接收區設成"landed"已降落
                            
                            //當Tello都已迫降 直接結束
                            var stop = true
                            
                            for i in 0..<data.count{
                                stop = stop && data[i] == "landed"
                            }
                            if stop == true{
                                show_add("場上已無Tello, 結束。")
                                timerStop()
                                return
                            }
                            
                            //直接檢查下一台
                            continue
                        }
                    //通過安全檢查
                    }else{
                        data[i] = ""//清空接收區
                        send(i, csv[handle][i + 1])//傳送相對指令
                    }
                }
            }
            handle += 1//下一條指令
            
            if csv[handle][0] == "end" || csv[handle][0] == ""{//時間軸遇到 "end" or 沒標示時間 -> 結束timer
                timerStop()
                show_add("結束")
            }
        }
    }
//=============== socket ===============
    //計算tello數量
    func calc_Tello_Num(){
        tello_Num = csv[0].count - 1
    }
    
    //創建udp socket
    func create_Tello_UDP(){
        close_Tello_UDP()
        calc_Tello_Num()
        
        for i in 0..<tello_Num{
            tello.append(UDPClient(address: csv[0][i + 1], port: Int32(port), myAddresss: "", myPort: Int32(sendPort_1st + i)))
        }
    }
    
    //關閉 udp socket
    func close_Tello_UDP(){
        //關閉socket
        for i in 0..<tello.count{
            tello[i].close()
        }
        
        //將Tello 陣列初始化
        tello = [UDPClient]()
    }
//============== sned & recv ==============
    //傳送String陣列給 所有無人機
    func send(_ s: [String]){
        for i in 0..<tello_Num{
            _ = tello[i].send(string: s[i + 1])
        }
    }
    
    //傳送單一指令給 所有無人機
    func send(_ s: String){
        for i in 0..<tello_Num{
            _ = tello[i].send(string: s)
        }
    }
    
    //傳送單一指令給 指定無人機
    func send(_ n:Int, _ s: String){
            _ = tello[n].send(string: s)
    }
    
    //接收資料 多執行緒
    func recvData(){
        data = [String]() //接收區大小重設
        
        for i in 0..<tello.count{
            data.append("")//增加陣列
            let queue = DispatchQueue(label: "com.nkust.tello" + String(i + 1))//宣告 label需要唯一性 無人機個別擁有 獨立執行緒
            
            queue.async {
                while true{
                    print(String(i + 1) + " is listening.")
                    let s = self.tello[i].recv(20)//等待接收 最多20字元data
                    if s.0==nil{break}//被強制結束 跳出
                    
                    self.data[i] = self.get_String_Data(s.0!)//儲存
                    self.show_add(String(i + 1) + " : " + self.data[i])//印出接收到的資料(ex. 1:OK)
                }
                print("Tello" + String(i + 1) + " is closed.")
            }
        }
    }
    
    //轉換陣列->String
    func get_String_Data(_ data: [Byte]) -> (String){
        var string1 = String(data: Data(data), encoding: .utf8) ?? ""
        string1 = string1.trimmingCharacters(in: .newlines)
        return string1
    }
    
    //清空接收的data
    func data_clear(){
        for i in 0..<data.count{
            data[i] = ""
        }
    }
//================== BT =====================

    @IBAction func command(_ sender: Any) {//連接
        send("command")
    }
    @IBAction func takeoff(_ sender: Any) {//起飛
        send("takeoff")
    }
    @IBAction func land(_ sender: Any) {//降落
        send("land")
    }
    @IBAction func emergency(_ sender: Any) {//緊急停止螺旋槳
        send("emergency")
    }
    
    @IBAction func flipF(_ sender: Any) {//前翻
        send("flip f");
    }
    @IBAction func flipL(_ sender: Any) {//左翻
        send("flip l")
    }
    @IBAction func flipB(_ sender: Any) {//後翻
        send("flip b")
    }
    @IBAction func flipR(_ sender: Any) {//右翻
        send("flip r")
    }
    @IBAction func stop(_ sender: Any) {//停止動作
        send("stop")
    }
    
    @IBAction func forward(_ sender: Any) {//前
        send("forward " + String(defaultSpeedValue))
    }
    @IBAction func back(_ sender: Any) {//後
        send("back " + String(defaultSpeedValue))
    }
    @IBAction func right(_ sender: Any) {//右
        send("right " + String(defaultSpeedValue))
    }
    @IBAction func left(_ sender: Any) {//左
        send("left " + String(defaultSpeedValue))
    }
    
    @IBAction func up(_ sender: Any) {//上升
        send("up " + String(defaultSpeedValue))
    }
    @IBAction func down(_ sender: Any) {//下降
        send("down " + String(defaultSpeedValue))
    }
    @IBAction func cw(_ sender: Any) {//順時針
        send("cw 45")
    }
    @IBAction func ccw(_ sender: Any) {//逆時針
        send("ccw 45")
    }
    @IBAction func battery(_ sender: Any) {//電量
        send("battery?")
    }
    
    //設定單機Tello 切換至station mode （連結）指定WiFi
    @IBAction func set_Station_Mode(_ sender: Any) {
        let alert = UIAlertController(title: "填入 ＷiFi名稱 與 密碼", message: "＊請先連結Tello的WiFi\n\n注意：當需要重新設置 或 發生問題時\n請在開機後長按電源按紐 5秒，即可恢復原廠設置。", preferredStyle: .alert)
        
        //SSID & password輸入框
        alert.addTextField { (UITextField) in
            UITextField.placeholder = "SSID"
        }
        alert.addTextField { (UITextField) in
            UITextField.placeholder = "password"
            UITextField.isSecureTextEntry = true
        }
        
        // ok & cancel 按鍵
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { (UIAlertAction) in
            guard let ssid = alert.textFields![0].text else{ return}
            guard let password = alert.textFields![1].text else{ return}
            
            if ssid == ""{
                self.show("SSID不可空白")
                return
            }
            _ = self.default_socket.send(string: "command")
            _ = self.default_socket.send(string: "ap " + ssid + " " + password)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .destructive, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
//=================== Switch ==================
    @IBAction func begin(_ sender: UISwitch) {
        if sender.isOn == true{
            audioPlayer.play()//播放音樂
            timerStart()//timer啟動·
            show("開始")
        }else{
            //tello降落
            timerStop()
            send("stop")
            send("land")
            show("降落中...三秒後關閉引擎")
            sleep(3)
            send("emergency")//安全起見 三秒後關閉引擎
            show("手動結束！")
            alert("已手動結束！")
        }
    }

//=================== read CSV ====================
    //開啟text選擇器
    @IBAction func readCSV(_ sender: Any) {
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.plain-text"], in: .open)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true, completion: nil)
    }
    
    //CSV字串 to 二維陣列
    func csv_To_Array(_ s: String)->([[String]]){
        var array = [[String]]()
        
        let line = s.components(separatedBy: "\r\n")
        for i in line{
            array.append(i.components(separatedBy: ","))
        }
        
        return array
    }
    @IBAction func showCSV(_ sender: Any) {
        alert(content)
    }
    //================== read mp3 =====================
    //開啟mp3選擇器
    @IBAction func readMusic(_ sender: Any) {
        let musicPicker = UIDocumentPickerViewController(documentTypes: ["public.mp3"], in: .open)
        musicPicker.delegate = self
        musicPicker.allowsMultipleSelection = false
        present(musicPicker, animated: true, completion: nil)
    }
//================== 檢查IP格式 ==========================
    //是否為ip格式
    func isIP(_ IP:String?) -> Bool{
        guard let IP = IP else { return false}//nil
        
        let s = IP.components(separatedBy: ".")
        if s.count != 4{ return false}//not *.*.*.*
        
        for i in s{
            guard let n = Int(i) else{ return false}//not Int
            
            if n < 0 || n > 255{ return false}//not 0~255
        }
        
        return true
    }
    
    //確認csv檔 ip格式是否正確
    func check_CSV_IPformat(_ csv:[[String]]) ->Bool{
        var check = true
        
        if csv[0].count < 2 {//沒填入IP
            return false
        }
        
        for i in 1..<csv[0].count{
            check = check && isIP(csv[0][i])
        }
        
        return check
    }
//===================== 顯示 ===========================
    //跳出視窗
    func alert(_ string:String?){
        let alert = UIAlertController(title: "訊息窗", message: string, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
    
    //顯示在textview上（覆蓋）
    func show(_ s:String){
        DispatchQueue.main.async{
            self.logTextView.text = s
        }
    }
    
    //顯示在textview（新增在底下）
    func show_add(_ s:String){
        DispatchQueue.main.async {
            self.logTextView.text = (self.logTextView.text ?? "") + "\n" + s
            self.logTextView.scrollRangeToVisible(self.logTextView.selectedRange)
        }
    }
    
    //textview 清空
    func log_clear(){
        DispatchQueue.main.async {
            self.logTextView.text = ""
        }
    }
//===================== 畫面消失 do ============================
    override func viewDidDisappear(_ animated: Bool) {
        timerStop()
    }
}

//===================== 實作檔案選取 ==============================
extension ViewController: UIDocumentPickerDelegate{
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let selectedFileURL = urls.first else{ return}
        
        let fileName = selectedFileURL.lastPathComponent.components(separatedBy: ".")
        let fileType = fileName[fileName.count - 1]//取副檔名
        
        //*** csv檔處理 ***
        if fileType == "csv"{
            content = try! String(contentsOf: selectedFileURL)
            
            csv = csv_To_Array(content)//轉陣列
            print(csv)
            create_Tello_UDP()//重新宣告UDP
            recvData()//開啟資料接收
            csvNameLabel.text = selectedFileURL.lastPathComponent//顯示csv檔名
            
        //*** mp3檔處理 ***
        }else if fileType == "mp3"{
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: selectedFileURL)
                audioPlayer.prepareToPlay()
                musicNameLabel.text = selectedFileURL.lastPathComponent//顯示mp3檔名
            } catch {
                print("Error:", error.localizedDescription)
            }
        }else{
            alert("僅能讀取 .csv 或 .mp3")
        }
    }
}
