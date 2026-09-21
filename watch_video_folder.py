# watch_video_folder.py VS Code后台常驻监听
import time
import os
import subprocess
import json
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
import git

repo_path = r"D:\ai-videos"
poster_dir = os.path.join(repo_path, "posters")
meta_file = os.path.join(repo_path, "video_meta.json")
os.makedirs(poster_dir, exist_ok=True)

if os.path.exists(meta_file):
    with open(meta_file, "r", encoding="utf-8") as f:
        meta = json.load(f)
else:
    meta = {}

class NewVideoHandler(FileSystemEventHandler):
    def on_created(self, event):
        if event.is_directory:
            return
        file_path = event.src_path
        if file_path.endswith(".mp4"):
            base_name = os.path.basename(file_path).replace(".mp4", "")
            mp4_full_path = file_path
            txt_full_path = os.path.join(repo_path, f"{base_name}.txt")
            poster_path = os.path.join(poster_dir, f"{base_name}.jpg")

            print(f"\n🔍 检测新增视频：{base_name}.mp4")
            print(f"⏳ 等待配套元文件 {base_name}.txt ...")
            
            wait_count = 0
            while not os.path.exists(txt_full_path) and wait_count < 60:
                time.sleep(1)
                wait_count += 1
            if not os.path.exists(txt_full_path):
                print(f"❌ 超时：未找到 {base_name}.txt，跳过该视频")
                return
            
            with open(txt_full_path, "r", encoding="utf-8") as f:
                txt_lines = f.read().splitlines()
            
            title = txt_lines[0].strip() if len(txt_lines)>=1 else "未命名视频"
            category = txt_lines[1].strip() if len(txt_lines)>=2 else "未分类"
            prompt = "\n".join(txt_lines[2:]).strip() if len(txt_lines)>=3 else ""

            print(f"✅ 读取元信息成功\n标题:{title}\n分类:{category}")
            print("🎬 FFmpeg提取视频首帧...")
            subprocess.run([
                "ffmpeg", "-ss", "00:00:00.1", "-i", mp4_full_path,
                "-vframes", "1", "-q:v", "6", poster_path, "-y"
            ], capture_output=True)

            meta[base_name] = {
                "title": title,
                "category": category,
                "prompt": prompt,
                "poster": f"posters/{base_name}.jpg",
                "video": f"{base_name}.mp4"
            }
            with open(meta_file, "w", encoding="utf-8") as f:
                json.dump(meta, f, ensure_ascii=False, indent=2)

            print("📤 Git提交：首帧图 + video_meta.json")
            repo = git.Repo(repo_path)
            repo.index.add([poster_path, meta_file])
            repo.index.commit(f"auto add poster & meta {base_name}")
            repo.remotes.origin.push("main")
            print(f"✅ {base_name} 全部处理完成！")

if __name__ == "__main__":
    event_handler = NewVideoHandler()
    observer = Observer()
    observer.schedule(event_handler, repo_path, recursive=False)
    observer.start()
    print(f"🔍 后台监控启动，监控目录：{repo_path}")
    print("💡 使用说明：放入 sxxxxxx.mp4 和 sxxxxxx.txt 一对文件")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()
