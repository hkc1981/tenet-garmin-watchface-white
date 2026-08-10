from PIL import Image
import sys

def remove_background_and_tint_advanced():
    try:
        # 1. 載入原始大圖 (使用從 Downloads 導入的 JPG 圖片)
        img = Image.open("scratch/S__16015415.jpg").convert("RGBA")
        width, height = img.size
        pixels = img.load()

        # 2. 定義洪水填充 (Flood Fill) 去背 (先清除大塊的外圍近白色背景)
        visited = set()
        queue = []

        def is_near_white(r, g, b):
            return r > 180 and g > 180 and b > 180

        # 上下邊界
        for x in range(width):
            for y in [0, height - 1]:
                r, g, b, a = pixels[x, y]
                if is_near_white(r, g, b) and (x, y) not in visited:
                    queue.append((x, y))
                    visited.add((x, y))
        
        # 左右邊界
        for y in range(height):
            for x in [0, width - 1]:
                r, g, b, a = pixels[x, y]
                if is_near_white(r, g, b) and (x, y) not in visited:
                    queue.append((x, y))
                    visited.add((x, y))

        directions = [(0, 1), (0, -1), (1, 0), (-1, 0)]
        while queue:
            cx, cy = queue.pop(0)
            r, g, b, a = pixels[cx, cy]
            pixels[cx, cy] = (r, g, b, 0) # 背景設為完全透明

            for dx, dy in directions:
                nx, ny = cx + dx, cy + dy
                if 0 <= nx < width and 0 <= ny < height:
                    if (nx, ny) not in visited:
                        nr, ng, nb, na = pixels[nx, ny]
                        if is_near_white(nr, ng, nb):
                            queue.append((nx, ny))
                            visited.add((nx, ny))

        # 3. 【殿堂級立體光影映射】：
        # 我們不要抹平細節。我們將像素的 RGB 統一染成深灰色 (85, 85, 85)，
        # 但是，我們將該像素的 Alpha 透明度，與它的「暗度 (255 - 灰階亮度)」進行映射！
        # 這樣一來，機身的接縫、刻線和陰影會呈現飽和的深灰色，而反光面會透出底部的黑色背景，
        # 在手錶螢幕上會呈現出極具層次感、立體金屬雕刻般的深灰光影質感！
        for y in range(height):
            for x in range(width):
                r, g, b, a = pixels[x, y]
                if a > 0:
                    # 計算灰階亮度 (0-255)
                    gray = int(0.299 * r + 0.587 * g + 0.114 * b)
                    
                    # 【線稿化處理：淘空內部填充，僅保留外框輪廓線】
                    # 將亮度閾值降低至 140。任何原本偏亮偏白的部分（如臉部皮膚填充、衣服填充、外圍背景），
                    # 一律強制設定為完全透明 (Alpha=0)！這能徹底防止娃娃內部被填滿，僅保留骨架輪廓線！
                    if gray > 140:
                        pixels[x, y] = (160, 160, 160, 0)
                    else:
                        # 對留存下來的輪廓線 (gray <= 140) 套用高不透明度，並進行平滑防鋸齒邊緣淡出
                        if gray < 110:
                            new_alpha = 255
                        else:
                            # 110~140 之間平滑漸變，保證線條自然，不起毛刺
                            new_alpha = int((140 - gray) * (255.0 / (140 - 110)))
                        
                        pixels[x, y] = (160, 160, 160, new_alpha)

        # 4. 等比例縮放且居中貼圖至 60x50 畫布上，防範拉伸畸變與比例失調問題
        target_w, target_h = 60, 50
        orig_w, orig_h = img.size
        
        # 計算等比例縮放比率
        ratio = min(float(target_w) / orig_w, float(target_h) / orig_h)
        new_w = int(orig_w * ratio)
        new_h = int(orig_h * ratio)
        
        # 防止極端縮放後為 0
        new_w = max(1, new_w)
        new_h = max(1, new_h)
        
        img_scaled = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
        
        # 建立一張完全透明的 60x50 背景畫布
        final_canvas = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
        
        # 計算貼圖的左上角坐標使其置中
        paste_x = (target_w - new_w) // 2
        paste_y = (target_h - new_h) // 2
        
        # 貼上
        final_canvas.paste(img_scaled, (paste_x, paste_y))
        
        # 5. 保存覆蓋
        final_canvas.save("resources/drawables/three-fighter.png", "PNG")
        print("Advanced 3D tinting and background removal completed successfully!")
    
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    remove_background_and_tint_advanced()
