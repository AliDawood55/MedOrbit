import {
    useState
} from "react";


import api from "../../api/axios";


function ForgotPassword() {


    const [email, setEmail] = useState("");

    const [message, setMessage] = useState("");



    async function submit(e) {

        e.preventDefault();


        try {


            await api.post(
                "/auth/forgot-password",
                {
                    email
                }
            );


            setMessage(
                "Check your email"
            );


        }

        catch (err) {

            setMessage(
                "Something went wrong"
            );

        }


    }



    return (

        <div className="auth">


            <h1>
                Forgot Password
            </h1>


            <form onSubmit={submit}>


                <input

                    type="email"

                    placeholder="Email"

                    value={email}

                    onChange={
                        e => setEmail(e.target.value)
                    }

                />


                <button>
                    Send Reset Link
                </button>


                <p>{message}</p>


            </form>


        </div>


    );


}


export default ForgotPassword;