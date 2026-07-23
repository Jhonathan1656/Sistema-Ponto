import random
from datetime import datetime, timedelta
from sqlalchemy.orm import sessionmaker
from main import User, TimeRecord, engine

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def seed_data():
    db = SessionLocal()
    try:
        # Hashed password manual para "123456" (padrão passlib)
        dummy_hash = "$pbkdf2-sha256$29000$hS2A7M9v1uA.9v.0u.1u.1$B9v.9v.9v.9v.9v.9v.9v.9v.9v.9v.9v.9v.9v.9v.9v.9"
        
        fictitious_users = [
            {"name": "Joao Silva", "email": "joao@exemplo.com", "role": "employee", "hours": 8.0, "cpf": "111.111.111-11"},
            {"name": "Maria Souza (Estagiaria)", "email": "maria@exemplo.com", "role": "intern", "hours": 6.0, "cpf": "222.222.222-22"},
            {"name": "Carlos Oliveira", "email": "carlos@exemplo.com", "role": "employee", "hours": 8.0, "cpf": "333.333.333-33"},
        ]

        created_users = []
        for u_data in fictitious_users:
            exists = db.query(User).filter(User.email == u_data["email"]).first()
            if not exists:
                user = User(
                    name=u_data["name"],
                    email=u_data["email"],
                    role=u_data["role"],
                    daily_hours=u_data["hours"],
                    cpf=u_data["cpf"],
                    hashed_password=dummy_hash
                )
                db.add(user)
                db.flush()
                created_users.append(user)
            else:
                created_users.append(exists)
        
        db.commit()

        today = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        for user in created_users:
            db.query(TimeRecord).filter(TimeRecord.user_id == user.id, TimeRecord.timestamp >= today).delete()
            
            # 08h - 12h / 13h - 17h
            records = [
                {"type": "check_in", "time": today + timedelta(hours=8)},
                {"type": "break_start", "time": today + timedelta(hours=12)},
                {"type": "break_end", "time": today + timedelta(hours=13)},
                {"type": "check_out", "time": today + timedelta(hours=17)},
            ]
            
            for r in records:
                db.add(TimeRecord(user_id=user.id, record_type=r["type"], timestamp=r["time"], location="VMac Matriz"))

        db.commit()
        print("DADOS_GERADOS: OK")
    except Exception as e:
        print(f"ERRO: {e}")
        db.rollback()
    finally:
        db.close()

if __name__ == "__main__":
    seed_data()
