import UIKit

class SnapPuzzleViewController: UIViewController {
    
    // --- 設計定数 ---
    let boardSize = 8
    let cellSize: CGFloat = 50.0
    let snapTolerance: CGFloat = 35.0 // 吸いつき許容距離（ピクセル）
    
    // 状態管理
    var grid = Array(repeating: Array(repeating: 0, count: 8), count: 8)
    var currentBlock = Block.lShape
    
    // UIコンポーネント（盤面、動くブロック、吸いつきプレビュー）
    let boardView = UIView()
    let dragBlockView = UIView()
    let previewView = UIView()
    
    // ドラッグ開始時の初期座標保持用
    var blockInitialCenter: CGPoint = .zero
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupGameScene()
    }
    
    private func setupGameScene() {
        // 1. 盤面の配置 (400x400)
        boardView.frame = CGRect(x: 20, y: 100, width: cellSize * CGFloat(boardSize), height: cellSize * CGFloat(boardSize))
        boardView.backgroundColor = UIColor.systemGray6
        boardView.layer.borderColor = UIColor.systemGray4.cgColor
        boardView.layer.borderWidth = 1
        view.addSubview(boardView)
        
        // 2. プレビュー用ビューの初期化（最初は非表示）
        previewView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.3)
        previewView.isHidden = true
        boardView.addSubview(previewView)
        
        // 3. 手持ちブロックの配置（初期位置：中央下部）
        dragBlockView.frame = CGRect(x: 150, y: 600, width: cellSize * 3, height: cellSize * 2)
        dragBlockView.backgroundColor = .clear
        renderBlockCells(inside: dragBlockView, block: currentBlock, color: .systemBlue)
        view.addSubview(dragBlockView)
        
        // 4. ドラッグジェスチャーの配備
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleBlockPan(_:)))
        dragBlockView.addGestureRecognizer(panGesture)
    }
    
    // --- 【核心】ドラッグ ＆ 磁気スナップの空間計算 ---
    @objc func handleBlockPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        
        switch gesture.state {
        case .began:
            blockInitialCenter = dragBlockView.center
            // ドラッグ開始時に少し大きく浮かせる（視覚的フィードバック）
            UIView.animate(withDuration: 0.1) {
                self.dragBlockView.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                self.dragBlockView.alpha = 0.9
            }
            
        case .changed:
            // 1. 指の動きに合わせて追従（自由座標）
            let currentCenter = CGPoint(x: blockInitialCenter.x + translation.x, y: blockInitialCenter.y + translation.y)
            dragBlockView.center = currentCenter
            
            // 2. 盤面（boardView）上のローカル座標に変換
            let localPos = view.convert(currentCenter, to: boardView)
            
            // 3. 最も近いグリッドのインデックスを逆算
            let estimatedGridX = Int(round((localPos.x - cellSize / 2) / cellSize))
            let estimatedGridY = Int(round((localPos.y - cellSize / 2) / cellSize))
            
            // 4. そのグリッド中心点までの幾何距離（ユークリッド距離）を測定
            let targetPixelX = CGFloat(estimatedGridX) * cellSize + cellSize / 2
            let targetPixelY = CGFloat(estimatedGridY) * cellSize + cellSize / 2
            let distance = hypot(localPos.x - targetPixelX, localPos.y - targetPixelY)
            
            // 5. 盤面内かつ閾値未満なら「ピタッ」とプレビューを吸着させる
            if estimatedGridX >= 0 && estimatedGridX < boardSize &&
               estimatedGridY >= 0 && estimatedGridY < boardSize &&
               distance < snapTolerance {
                
                // 配置バリデーションチェック
                let isValid = checkValidPlacement(atX: estimatedGridX, atY: estimatedGridY)
                previewView.backgroundColor = isValid ? UIColor.systemBlue.withAlphaComponent(0.3) : UIColor.systemRed.withAlphaComponent(0.4)
                
                // プレビュー枠をグリッド位置にピタッと固定描画
                previewView.frame = CGRect(x: CGFloat(estimatedGridX) * cellSize, y: CGFloat(estimatedGridY) * cellSize, cellSize * 3, cellSize * 2) // ブロックの形状幅に合わせる
                previewView.isHidden = false
                
                // 【手触りの極意】手持ちブロック側の描画座標も、スナップ位置へわずかに慣性補正をかけるとさらに気持ちよくなります
                
            } else {
                previewView.isHidden = true
            }
            
        case .ended, .cancelled:
            // 元のスケールに戻す
            UIView.animate(withDuration: 0.1) {
                self.dragBlockView.transform = .identity
                self.dragBlockView.alpha = 1.0
            }
            
            let localPos = view.convert(dragBlockView.center, to: boardView)
            let estimatedGridX = Int(round((localPos.x - cellSize / 2) / cellSize))
            let estimatedGridY = Int(round((localPos.y - cellSize / 2) / cellSize))
            let targetPixelX = CGFloat(estimatedGridX) * cellSize + cellSize / 2
            let targetPixelY = CGFloat(estimatedGridY) * cellSize + cellSize / 2
            let distance = hypot(localPos.x - targetPixelX, localPos.y - targetPixelY)
            
            // 離した瞬間にスナップ範囲内かつ配置可能なら確定
            if distance < snapTolerance && checkValidPlacement(atX: estimatedGridX, atY: estimatedGridY) {
                // 盤面に結合（アライメント確定）
                commitPlacement(atX: estimatedGridX, atY: estimatedGridY)
                // 成功時は手持ち位置に新しいブロックをリザレクト
                resetBlockPosition()
            } else {
                // 失敗時はバネのようになめらかに手持ち位置へ差し戻す（ロジスティクス的復位）
                UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                    self.dragBlockView.center = CGPoint(x: 150, y: 600)
                }
            }
            previewView.isHidden = true
            
        default:
            break
        }
    }
    
    private func checkValidPlacement(atX gx: Int, atY gy: Int) -> Bool {
        return currentBlock.cells.allSatisfy { cell in
            let tx = gx + cell.x
            let ty = gy + cell.y
            return tx >= 0 && tx < boardSize && ty >= 0 && ty < boardSize && grid[ty][tx] == 0
        }
    }
    
    private func commitPlacement(atX gx: Int, atY gy: Int) {
        for cell in currentBlock.cells {
            grid[gy + cell.y][gx + cell.x] = 1
            // 盤面ビューに対応する固定ブロックのSubViewを追加する処理など
        }
        print("🎯 盤面座標 [\(gx), \(gy)] にピタッと結合されました。")
    }
    
    private func resetBlockPosition() {
        dragBlockView.center = CGPoint(x: 150, y: 600)
    }
    
    private func renderBlockCells(inside container: UIView, block: Block, color: UIColor) {
        // コンテナ内にセルの矩形をレンダリングする補助ロジック
    }
}