from sqlalchemy.orm import sessionmaker
from sqlalchemy import create_engine
from main import User, engine

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def promote_user(email: str, new_role: str):
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.email == email).first()
        if user:
            user.role = new_role
            db.commit()
            print(f"USUARIO_OK: {email} agora e {new_role}")
        else:
            print(f"ERRO: Usuario {email} nao encontrado")
    except Exception as e:
        print(f"ERRO_GERAL: {e}")
    finally:
        db.close()

if __name__ == "__main__":
    promote_user("rodrigo@gmail.com", "admin")
